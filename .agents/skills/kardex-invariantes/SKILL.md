---
name: kardex-invariantes
description: Revisar cualquier cambio que toque stock, kardex, recepción, despacho, consumo, presupuesto o desviación en Check-In-Obra. Usar antes de dar por terminado un cambio en `inventario/`, en `presupuesto/`, o en la cola de movimientos de la app móvil — el stock es un saldo derivado y se rompe en silencio.
---

# Invariantes del kardex

El sistema entero descansa en una decisión: **el stock no es una columna.**

```java
// KardexMovimientoService
public double stockActual(Long obraId, Long materialId) {
    return kardexMovimientoRepository.findByObraIdAndMaterialId(obraId, materialId).stream()
            .mapToDouble(m -> m.getCantidad() * m.signo())
            .sum();
}
```

Es la suma con signo de los `KardexMovimiento`: `RECEPCION` suma, `DESPACHO` y
`CONSUMO` restan. Esa elección da trazabilidad total — todo saldo se puede
explicar movimiento por movimiento — a cambio de que **nada valida el saldo por
ti**. No hay un `CHECK (stock >= 0)` que te avise. Un movimiento mal escrito no
rompe nada visible hoy: rompe la desviación de la obra tres semanas después,
cuando ya no se puede reconstruir qué pasó.

De ahí esta skill. Lee las invariantes, y para cada una decide si tu cambio la
mantiene, la rompe, o no la toca.

## Las invariantes

### I1 — Un movimiento es inmutable

Un `KardexMovimiento` grabado no se edita ni se borra. Un error se corrige con
un movimiento compensatorio en sentido contrario, igual que un asiento contable.

Si tu cambio agrega un `PUT /api/kardex/{id}` o un `DELETE`, o un
`kardexMovimientoRepository.save()` sobre una entidad ya persistida, está mal.
`repository.save()` sobre una entidad con `id` no nulo es un `UPDATE`.

### I2 — La cantidad es siempre positiva; el signo lo pone el tipo

`KardexMovimiento.registrar()` rechaza `cantidad <= 0`, y `signo()` deriva el
signo de `tipoMovimiento`. Nunca guardes una cantidad negativa para representar
una salida: rompe todo reporte que agrupe por tipo y hace que
`SUM(cantidad)` deje de significar nada.

### I3 — El saldo nunca queda negativo

`registrarMovimiento` compara contra `stockActual` antes de un `DESPACHO` o
`CONSUMO` y lanza `IllegalStateException` (→ 409). Cualquier camino nuevo que
cree movimientos debe pasar por ese mismo método. Si escribes un endpoint de
carga masiva, un importador o un job que llame al repositorio directo, saltaste
la validación.

**Hueco conocido:** la comprobación es lectura y después escritura, sin bloqueo.
Dos despachos concurrentes del mismo material leen el mismo saldo, ambos pasan,
y el stock queda negativo. Hoy nadie lo cubre. Si tu cambio aumenta la
concurrencia — sincronización por lotes desde la app, varios bodegueros — hay
que cerrarlo con un `SELECT ... FOR UPDATE` sobre el material o con un
`@Version` optimista, y decirlo explícitamente.

### I4 — Todo movimiento pertenece a una obra, un material y un usuario

Las tres FK son `nullable = false`. El `usuario_id` es la trazabilidad: quién
registró qué. Sin eso, el kardex deja de ser auditable y pasa a ser una lista de
números.

**Dos personas, no una.** `usuario` es quien **registra** el movimiento;
`trabajador` es quien lo **recibe**. Un despacho exige receptor (400 si falta),
un consumo puede no tenerlo, y una recepción lo rechaza — el material entra
desde un proveedor. Sin el receptor, el kardex no puede responder "¿a quién se
le entregaron esas 36 planchas?", que es la primera pregunta cuando aparece un
descuadre.

**Hueco conocido:** `RegistrarMovimientoRequest` recibe el `usuarioId` **en el
cuerpo de la petición**, no del JWT. Cualquier bodeguero puede atribuirle un
movimiento a otra persona. Si tocas ese endpoint, saca el `usuarioId` del token
autenticado y bórralo del request.

### I5 — Nada se registra contra una obra cerrada

`Obra.cerrar()` es el punto en que el presupuesto y el consumo quedan
congelados para comparar. Un movimiento posterior corre la desviación de una
obra que ya se dio por terminada. `registrarMovimiento` **hoy no comprueba el
`EstadoObra`** — si tu cambio pasa por ahí, agrégalo.

### I6 — El presupuesto congelado es la línea base y no se toca

`ComparadorPresupuestoService` compara consumo real contra presupuesto
congelado. Si el presupuesto se pudiera editar después de congelado, la
desviación mediría contra un blanco móvil y no significaría nada. Un
`PresupuestoItem` de un presupuesto en estado congelado es de solo lectura.

### I7 — Los ids de otra empresa no existen

Es multi-tenant, y el aislamiento ya está cerrado: la empresa sale del token,
toda entidad implementa `PerteneceAEmpresa`, y `KardexMovimientoService` pasa
por `obraService.obtener(obraId)`, que filtra.

Lo que tienes que mantener al tocar inventario:

- Todo camino nuevo hacia el kardex entra por `obraService.obtener(obraId)` o
  por `materialService.obtener(materialId)`. Si consultas el repositorio
  directo, te saltaste el filtro.
- Un recurso ajeno se descarta con `.filter(AccesoEmpresa::esPropio)` sobre el
  `Optional`, **nunca** lanzando un error propio. Un 403 para lo ajeno y un 404
  para lo inexistente son un oráculo: con esa diferencia se recorren los ids y
  se cuentan las obras de la competencia.
- Ojo con las consultas que no llevan obra ni empresa.
  `findByFechaDevolRealIsNullAndFechaDevolEsperadaBefore` barría los préstamos
  vencidos de todas las constructoras; ahora se filtra en memoria. Cualquier
  consulta global que agregues necesita el mismo cuidado.

## Fugas de datos en la respuesta

`KardexMovimientoController` devolvía la entidad tal cual, y su
`@ManyToOne(fetch = EAGER)` hacia `Usuario` arrastraba el objeto completo — con
el hash BCrypt del PIN adentro. Hoy devuelve `KardexMovimientoResponse`, con
cada relación aplanada a su id más la etiqueta mínima.

Regla: ningún endpoint de inventario devuelve entidades. `RespuestasNoExponenEntidadesTest`
falla si alguien vuelve a hacerlo — ver [[spring-boot-modulo]].

## Precisión numérica

`cantidad` es `double` en Java y `DOUBLE PRECISION` en Postgres, y el stock es
una suma de miles de ellos. El error de punto flotante se acumula: 0.1 + 0.2
no da 0.3, y en un kardex de obra eso termina como un saldo de `-0.0000000001`
que dispara una alerta de stock negativo inexistente.

Mientras el tipo siga siendo `double`:

- Nunca compares saldos con `==`. Usa una tolerancia (`Math.abs(a - b) < 1e-6`).
- El `cantidad > stockActual` de I3 debería ser `cantidad > stockActual + 1e-6`.
- Al mostrar en la app, redondea a la precisión de la unidad del material.

Para columnas nuevas de dinero, usa `NUMERIC(14,2)` y `BigDecimal` desde el
principio en vez de sumarse al problema.

## Rendimiento

`stockActual` trae **todos** los movimientos del par obra-material a memoria
para sumarlos en Java. Una obra larga con un material de alta rotación son miles
de filas por cada consulta de stock, y la pantalla de despacho la consulta en
cada escaneo. La suma pertenece a la base:

```java
@Query("""
       SELECT COALESCE(SUM(CASE WHEN k.tipoMovimiento = 'RECEPCION'
                                THEN k.cantidad ELSE -k.cantidad END), 0)
       FROM KardexMovimiento k
       WHERE k.obra.id = :obraId AND k.material.id = :materialId
       """)
double calcularStock(@Param("obraId") Long obraId, @Param("materialId") Long materialId);
```

El índice `idx_kardex_obra_material` ya existe y la sostiene.

## Del lado de la app

La cola offline crea movimientos igual que el backend, con la diferencia de que
llegan tarde y en lote. Todo lo de arriba aplica, más lo de
[[flutter-offline-first]]. En particular: un 409 por stock insuficiente al
sincronizar **no** es un error de red y no se reintenta — el movimiento se
rechaza y hay que mostrárselo a quien lo registró.

## Checklist del cambio

- [ ] No hay `UPDATE` ni `DELETE` sobre un movimiento existente (I1)
- [ ] Toda cantidad guardada es positiva (I2)
- [ ] Todo camino nuevo pasa por `registrarMovimiento`, no por el repositorio (I3)
- [ ] Si el cambio agrega concurrencia, el saldo se lee con bloqueo (I3)
- [ ] El `usuarioId` sale del token, no del cuerpo (I4)
- [ ] Se comprueba `EstadoObra` antes de registrar (I5)
- [ ] Ningún presupuesto congelado se modifica (I6)
- [ ] Las rutas nuevas filtran por la empresa del token (I7)
- [ ] La respuesta es un `record`, nunca la entidad
- [ ] Ninguna comparación de saldos usa `==` sobre `double`
- [ ] No se agregó una consulta que sume en memoria lo que puede sumar Postgres
- [ ] Hay un test que registra recepción + despacho y verifica el saldo
