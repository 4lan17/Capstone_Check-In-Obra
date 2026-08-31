---
name: spring-boot-modulo
description: Agregar o extender un módulo de dominio del backend de Check-In-Obra (entidad JPA, repositorio, servicio, controlador REST y migración Flyway) siguiendo las convenciones reales del proyecto. Usar cuando se pida crear una entidad, un endpoint, un CRUD, un servicio nuevo, o al tocar cualquier archivo bajo `backend/src/main/java/cl/duocuc/checkinobra/`.
---

# Módulo de dominio del backend

Java 21 · Spring Boot 4.1.1 · PostgreSQL 16 · Flyway · JJWT · Lombok.
Raíz del paquete: `cl.duocuc.checkinobra`.

## Regla de dependencia entre paquetes

Los seis paquetes son `config`, `obra`, `cubicacion`, `presupuesto`, `inventario`,
`control`. La única regla estructural del proyecto:

> `control` puede depender de todos los demás. **Nadie depende de `control`.**

Antes de agregar un `import` de `control` en otro paquete, para. Si una alerta
debe nacer de un evento de inventario, el que sabe de alertas es `control`, no
`inventario`. En la práctica el resto de los paquetes sí se cruzan
(`inventario` usa `ObraService` y `MaterialService`), y eso es aceptado.

## Las cuatro capas y qué le toca a cada una

| Capa | Responsabilidad | Lo que NO le toca |
|---|---|---|
| Entidad | Estado propio y sus transiciones (`Obra.cerrar()`, `Presupuesto.congelar()`) | Consultar repositorios, saber de HTTP |
| Servicio | Orquestar entre agregados, reglas que cruzan entidades | Anotaciones de HTTP, armar respuestas |
| Repositorio | Consultas | Lógica de negocio |
| Controlador | HTTP, autorización por rol, `record` de request | Reglas de negocio, tocar el repositorio directo |

La transición propia vive en la entidad **y** el servicio la envuelve con las
precondiciones que cruzan agregados. `ObraService.cerrar()` valida que no haya
herramientas fuera ni alertas sin resolver, y recién entonces llama a
`Obra.cerrar()`. Replica ese reparto: la entidad protege su propio estado, el
servicio protege el mundo alrededor.

## Archivos por módulo

Al agregar un agregado nuevo llamado `Xxx` dentro del paquete `<pkg>`:

```
backend/src/main/java/cl/duocuc/checkinobra/<pkg>/
    Xxx.java                  entidad JPA
    XxxRepository.java        interface JpaRepository
    XxxService.java           @Service @Transactional
    XxxController.java        @RestController
    EstadoXxx.java            enum, si tiene estados
backend/src/main/resources/db/migration/
    V<n>__<descripcion>.sql   migración, nunca editar una ya aplicada
```

## Plantillas — copiar el estilo, no inventar uno

### Entidad

Lombok con las cinco anotaciones juntas, `@Enumerated(EnumType.STRING)` siempre
(nunca ordinal), `fetch = FetchType.EAGER` en los `@ManyToOne` como hace el
resto del código, y la transición propia como método público.

```java
@Entity
@Table(name = "xxxs")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Xxx {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String nombre;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private EstadoXxx estado;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "obra_id", nullable = false)
    private Obra obra;

    /** Transición propia: valida contra su estado actual y falla si no aplica. */
    public void cerrar() {
        if (estado != EstadoXxx.ABIERTO) {
            throw new IllegalStateException("Solo se puede cerrar un Xxx abierto");
        }
        this.estado = EstadoXxx.CERRADO;
    }
}
```

### Servicio

Inyección por constructor explícito — el proyecto **no** usa
`@RequiredArgsConstructor` en servicios. `@Transactional` a nivel de clase y
`@Transactional(readOnly = true)` en cada lectura. El `obtener` que lanza
`NoSuchElementException` con el id en el mensaje es el patrón establecido:

```java
@Service
@Transactional
public class XxxService {

    private final XxxRepository xxxRepository;
    private final ObraService obraService;

    public XxxService(XxxRepository xxxRepository, ObraService obraService) {
        this.xxxRepository = xxxRepository;
        this.obraService = obraService;
    }

    public Xxx crear(Long obraId, String nombre) {
        Obra obra = obraService.obtener(obraId);
        Xxx xxx = Xxx.builder()
                .nombre(nombre)
                .estado(EstadoXxx.ABIERTO)
                .obra(obra)
                .build();
        return xxxRepository.save(xxx);
    }

    @Transactional(readOnly = true)
    public Xxx obtener(Long id) {
        return xxxRepository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("Xxx no encontrado: " + id));
    }
}
```

### Controlador

`record` anidado para el request, `@Tag` para Swagger, y `@PreAuthorize` en toda
ruta que no sea de lectura pública para la empresa:

```java
@RestController
@RequestMapping("/api/xxxs")
@Tag(name = "Xxx")
public class XxxController {

    private final XxxService xxxService;

    public XxxController(XxxService xxxService) {
        this.xxxService = xxxService;
    }

    @PostMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO')")
    @ResponseStatus(HttpStatus.CREATED)
    public XxxResponse crear(@RequestBody CrearXxxRequest req) {
        return XxxResponse.de(xxxService.crear(req.obraId(), req.nombre()));
    }

    public record CrearXxxRequest(Long obraId, String nombre) {
    }
}
```

## Manejo de errores — no inventar excepciones

`ApiExceptionHandler` ya mapea todo. Lanza la excepción estándar de Java que
corresponde y el status sale solo:

| Excepción | Status | Cuándo |
|---|---|---|
| `NoSuchElementException` | 404 | El id no existe |
| `IllegalStateException` | 409 | La operación choca con el estado actual (stock insuficiente, obra cerrada) |
| `IllegalArgumentException` | 400 | El argumento no tiene sentido en sí mismo |
| `MethodArgumentNotValidException` | 400 | Falla un `@Valid` sobre el request |

También mapea `AccesoDenegadoException` a 403 y los errores de petición
malformada (cuerpo ilegible, parámetro faltante o con el tipo equivocado) a 400.

No crees excepciones propias ni devuelvas `ResponseEntity` con status a mano
salvo que necesites un caso que la tabla no cubra.

**Dos Jackson en el classpath.** Spring Boot 4 usa **Jackson 3**
(`tools.jackson`) para convertir las peticiones HTTP, pero Jackson 2
(`com.fasterxml.jackson`) sigue ahí porque lo arrastran JJWT y los starters. Son
jerarquías de excepciones sin parentesco, y las anotaciones (`@JsonIgnore`) las
comparten. Al inspeccionar una excepción de Jackson hay que preguntar por las
dos clases; y un test que serialice con `Jackson2ObjectMapperBuilder` **no está
probando lo que la app manda por la red** — usa `tools.jackson.databind.json.JsonMapper`.

## Autorización

`SecurityConfig` deja abierto solo `/api/auth/**` y Swagger; **todo lo demás
exige token**. La autorización fina va con `@PreAuthorize` en el método del
controlador, usando `hasRole` / `hasAnyRole` con los valores de `RolUsuario`:
`ADMIN`, `JEFE_TERRENO`, `BODEGUERO`, `TRABAJADOR`.

La matriz vigente, tomada del README:

- Catálogo, precios, mermas, usuarios, crear/cerrar obra → `ADMIN`
- Cubicar, congelar presupuesto, ver desviación → `ADMIN`, `JEFE_TERRENO`
- Kardex, préstamos, aprobar solicitudes, cerrar turno → `ADMIN`, `BODEGUERO`
- Pedir herramienta o material, credencial QR → `TRABAJADOR`

**Un endpoint sin `@PreAuthorize` queda abierto a los cuatro roles.** Eso casi
nunca es lo que se quiere: si escribes un `@GetMapping` sin anotación, justifica
en el momento por qué un trabajador puede leer eso.

## Aislamiento por empresa

Es multi-tenant, y el mecanismo ya está montado. Hay tres reglas y no son
opcionales — `AislamientoEntreEmpresasTest` falla si rompes cualquiera.

**1. La entidad implementa `PerteneceAEmpresa`.** Devuelve el id recorriendo su
propia cadena de relaciones:

```java
public class Xxx implements PerteneceAEmpresa {
    @Override
    public Long empresaId() {
        return obra.empresaId();   // Xxx → Obra → Empresa
    }
}
```

**2. La empresa sale del token, nunca de la petición.** Ningún controlador
recibe `empresaId` por query param ni en el cuerpo del request. Se lee con
`SesionActual.empresaId()`:

```java
@GetMapping
public List<XxxResponse> listar() {
    return xxxService.listarPorEmpresa(SesionActual.empresaId()).stream()
            .map(XxxResponse::de)
            .toList();
}
```

**3. Un recurso ajeno se filtra, no se rechaza.** En el servicio:

```java
@Transactional(readOnly = true)
public Xxx obtener(Long id) {
    return xxxRepository.findById(id)
            .filter(AccesoEmpresa::esPropio)
            .orElseThrow(() -> new NoSuchElementException("Xxx no encontrado: " + id));
}
```

El `.filter` importa más de lo que parece. Si lanzaras un 403 propio para lo
ajeno, la respuesta distinguiría "existe pero no es tuyo" de "no existe", y con
esa diferencia se recorren los ids del sistema para contar las obras de la
competencia. Filtrado, un recurso ajeno produce el mismo 404 con el mismo
mensaje que un id inventado.

Para las listas por padre, basta pasar por el `obtener` del padre —
`obraService.obtener(obraId)` antes de listar lo que cuelga de esa obra: si la
obra es ajena, revienta ahí y nada más se ejecuta.

**Cuidado con las consultas globales.** Un `findByEstadoAndFechaBefore(...)` sin
obra ni empresa barre todo el sistema. Filtra el resultado con
`AccesoEmpresa.soloPropios(...)`.

## Nunca serializar la entidad directo

Con `@ManyToOne(fetch = EAGER)` en casi todas las relaciones, devolver una
entidad arrastra el grafo entero: pedir un movimiento de kardex traía la obra,
el material, el usuario y la empresa. Así se publicó durante un tiempo el hash
BCrypt del PIN de cada usuario.

Cada entidad tiene ya su `record` de respuesta al lado, con las relaciones
aplanadas a su id más la etiqueta mínima para leerlas.
`RespuestasNoExponenEntidadesTest` falla si un controlador devuelve una entidad,
o si un `*Response` lleva un objeto del dominio en vez de escalares. Al agregar
una entidad, agrega su record:

```java
public record XxxResponse(Long id, String nombre, String estado, Long obraId) {
    public static XxxResponse de(Xxx x) {
        return new XxxResponse(x.getId(), x.getNombre(), x.getEstado().name(), x.getObra().getId());
    }
}
```

## Migraciones Flyway

- `V<n>__descripcion_en_snake_case.sql`, `n` es el siguiente correlativo libre.
- **Nunca** se edita una migración ya aplicada; el checksum de Flyway falla.
- Orden de `CREATE TABLE` = orden de dependencia de llaves foráneas.
- Enum en Java → `VARCHAR(20) NOT NULL` en SQL, nunca un tipo enum de Postgres.
- Índice explícito para todo par de columnas por el que se filtre seguido, como
  `idx_kardex_obra_material ON kardex_movimientos (obra_id, material_id)`.
- Cantidades y precios hoy son `DOUBLE PRECISION`. Si agregas una columna de
  dinero nueva, `NUMERIC(14,2)` es lo correcto — ver [[kardex-invariantes]].

## Antes de dar el módulo por listo

- [ ] Las cuatro capas están, y ninguna hace el trabajo de otra
- [ ] Ningún `import` nuevo de `control` fuera de `control`
- [ ] Toda ruta tiene `@PreAuthorize`, o una razón escrita para no tenerlo
- [ ] La entidad implementa `PerteneceAEmpresa`
- [ ] La empresa sale de `SesionActual`, no de la petición
- [ ] El `obtener(id)` filtra con `AccesoEmpresa::esPropio` antes del `orElseThrow`
- [ ] Toda consulta global filtra con `AccesoEmpresa.soloPropios(...)`
- [ ] El controlador devuelve `record`, no entidad, y el record solo lleva escalares
- [ ] Migración con número libre, y no se tocó ninguna anterior
- [ ] Los errores usan las excepciones que `ApiExceptionHandler` ya mapea
- [ ] `./mvnw -q test` pasa (con `SPRING_DATASOURCE_URL` apuntando al 5433)
