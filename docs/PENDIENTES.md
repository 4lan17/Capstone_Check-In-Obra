# Check-In-Obra — Estado y trabajo pendiente

**Fecha:** 2026-08-27 (backend, multi-tenant y app móvil actualizados el 2026-11-22) · **Rama:** `main` · **Repo:** [1Bryvn/Check-In-Obra](https://github.com/1Bryvn/Check-In-Obra)

Informe del estado real del proyecto y lo que falta para cerrar el MVP 1.
Las cifras salen de auditar el código, no de estimaciones.

---

## 1. Resumen en números

| Área | Hecho | Total | Avance |
|---|---:|---:|---:|
| **Backend** — endpoints REST | 106 | 106 | ✅ 100 % |
| **Backend** — entidades (`@Entity`) | 20 | 20 | ✅ 100 % |
| **App móvil** — pantallas diseñadas | 29 | 34 | 🟢 85 % |
| **App móvil** — endpoints consumidos | 84 | 106 | 🟢 79 % (84 de los 101 que no son de plataforma) |
| **Pruebas** — backend | 397 | — | ✅ 56 clases; unitarias e integración contra Postgres real |
| **Pruebas** — móvil | 310 | — | ✅ 28 archivos; unitarias y de widget, sin integración contra el backend |
| **CI/CD** | 1 | — | ✅ GitHub Actions (backend y app); CodeQL y revisión de dependencias solo con la variable `GHAS=true` |

**Lectura corta:** el backend está completo y probado; la app móvil tiene los
flujos del bodeguero, del administrador y del trabajador, y del jefe de terreno
todo menos la desviación. Le faltan 5 de los 34 diseños (§3).

*Cómo se midió la app (2026-11-22):* sobre `develop` (6e4545f), con los PR móviles ya
integrados —ver [`ESPECIFICACION.md` §13](ESPECIFICACION.md#13-estado-de-cumplimiento)—.

---

## 2. Lo que ya está funcionando

Verificado de punta a punta contra el backend real, no asumido:

- **Infraestructura** — `docker compose up` levanta backend + PostgreSQL con
  puertos que no chocan con otros proyectos (8081/5433). Flyway aplica el
  esquema completo y el usuario semilla.
- **Backend** — 20 entidades, 21 controladores, 106 endpoints, autorización por
  rol con `@PreAuthorize`, JWT con refresh, Swagger (apagado en el perfil `prod`).
  *(Cifras de `develop` al 2026-11-22.)*
- **App móvil** — los cuatro roles entran a su propia app: bodeguero (stock, kardex,
  escáner, solicitudes, herramientas, alertas), administrador (obras, materiales,
  usuarios, importación de planillas), trabajador (credencial QR, pedidos,
  historial) y jefe de terreno (partidas, cubicación y presupuesto). Sesión en el
  Keystore con renovación automática del token, cambio de clave en el primer
  ingreso, y todo lo que recuerda el teléfono guardado por empresa y usuario.
- **Entorno de desarrollo** — celular físico y emulador Pixel 5 (API 33),
  ambos probados con login real.

---

## 3. App móvil — 5 pantallas pendientes

Los diseños están en `docs/mockups/design-movil/` (34). Cada uno cuenta como hecho si
hay una pantalla de la app que lo cubre.

| Rol | Hechas | Pendientes |
|---|---|---|
| Compartidas (6) | `Acceso`, `AccesoPin`, `SelectorObra`, `Alertas` | `SinPermiso`, `SinConexion` |
| Trabajador (6) | Las 6 | — |
| Bodeguero (10) | Las 10 | — |
| Jefe de terreno (6) | `JefePartidas`, `JefeCubicacion`, `JefePresupuesto` | `JefeInicio`, `JefeDesviacion`, `JefeCuadrillas` |
| Administrador (6) | Las 6 | — |

### 3.1 Lo que falta

| Pantalla | Estado | Qué implica |
|---|---|---|
| `SinPermiso` | ⬜ Pendiente | Acción bloqueada por rol, con quién sí puede. Hoy el rechazo se ve como un mensaje en la pantalla donde ocurrió |
| `SinConexion` | ⬜ Pendiente | **Cola offline — ver §6.1, es la más compleja.** Los requisitos para que nazca aislada por empresa están en `arquitectura/cola-offline-por-empresa.md` (PR #132) |
| `JefeInicio` | ⬜ Pendiente | Contadores de la obra y la desviación a la vista. Hoy el jefe entra directo a Partidas. Ver el endpoint de resumen en §4.2 |
| `JefeDesviacion` | ⬜ Pendiente | `GET /api/presupuestos/{id}/desviacion` · **gráficos, `fl_chart` sin usar**. Es el único requisito funcional de la app que falta del flujo del jefe (RF-D6) |
| `JefeCuadrillas` | ⬜ Pendiente | `GET /api/cuadrillas?obraId=`, y crear cuadrillas (RF-B5). Con ella, dar de alta un trabajador (RF-B6) |

También sin pantalla, aunque tienen endpoint: renovar la credencial de un trabajador
por su id desde la gestión (RF-B9). El trabajador renueva la suya desde su credencial.

### 3.2 Pendientes que no son un diseño

- **Pruebas de integración de la app contra el backend real:** hoy son todas con el
  backend simulado.
- **Ícono de la app:** sigue siendo el de Flutter por defecto.

---

## 4. Backend — pendientes

El backend está **funcionalmente completo**, pero le falta respaldo automatizado.

### 4.1 Pruebas — prioridad alta

*(Actualizado el 2026-11-20.)* El backend tiene **397 pruebas en 56 clases**, casi todas de integración
contra PostgreSQL real (HTTP con el servidor levantado, dos bases reales, los scripts de respaldo). Ya no
es «un solo test». **No hay medición de cobertura** (no hay JaCoCo en el `pom.xml`), así que no se sabe
cuántas validaciones de negocio siguen sin prueba: la cifra de «18 sin ninguna prueba» del informe de
agosto no se volvió a medir.

De las reglas que más duelen si se rompen en silencio, buscando su código o su nombre en las pruebas:

| Regla | Dónde vive | ¿Tiene prueba? |
|---|---|---|
| El kardex no admite stock negativo | `KardexMovimientoService` | Sí (`STOCK_INSUFICIENTE`, con concurrencia) |
| Una obra no cierra con herramientas fuera o alertas abiertas | `ObraService.cerrarObra` | Se nombra en las pruebas; no se verificó que cubran las dos condiciones |
| Un presupuesto solo se congela desde `APROBADO` | `Presupuesto.congelar` | **No encontré una prueba** |
| Una solicitud resuelta no se puede volver a resolver | `Solicitud*.aprobar/rechazar` | Sí (`YA_RESUELTA`) |
| Una herramienta prestada no se puede volver a prestar | `PrestamoHerramientaService` | Sí (`HERRAMIENTA_NO_DISPONIBLE`) |
| La clave cumple la política de su rol (el PIN de un trabajador es de 4 dígitos) | `Usuario.definirPin` | Sí |

La columna «¿Tiene prueba?» sale de un `grep`, no de una cobertura medida.

> **Recomendación pendiente:** hoy las pruebas **necesitan un PostgreSQL con los roles y bases ya
> creados** (la CI lo levanta como servicio; en local, `db/crear-roles.sh`). Testcontainers lo
> haría solo; no se adoptó. Medir la cobertura (JaCoCo) tampoco.

### 4.2 Endpoints que faltarían

- `GET /api/usuarios/{id}/trabajador` — hoy, para saber el `trabajadorId` de
  un usuario, la app tendría que recorrer la lista completa de trabajadores.
- Paginación en los listados. Con 34 materiales da igual, pero un kardex de
  varios meses devuelto entero es un problema.
- `GET /api/obras/{id}/resumen` — los contadores que muestra `BodInicio` (y los que
  mostraría `JefeInicio`) se arman hoy con varias llamadas separadas.

---

## 5. Infraestructura y calidad

| Pendiente | Estado | Nota |
|---|---|---|
| **CI/CD** | 🟢 Hecho | `.github/workflows/ci.yml`: backend y app; además `release-apk.yml`, manual, para el APK firmado |
| **`scripts/`** | 🟢 Hecho | `levantar.sh`, `release-apk.sh`, `cuentas_de_prueba.py` y los de respaldo |
| **Fuentes del design system** | 🟢 Hecho | Inter empaquetada en `mobile/assets/fonts`; reemplaza al par Fira que proponía el documento original |
| **Ícono de la app** | 🟠 Pendiente | Sigue el de Flutter por defecto |
| **Nombre visible** | 🟢 Hecho | «Check-In Obra» |

**El CI corre** `./mvnw verify` para el backend y, para la app, `dart format`,
`flutter analyze`, `flutter test` y `flutter build apk --debug`.

---

## 6. Riesgos y decisiones abiertas

### 6.1 La cola sin conexión es más difícil de lo que parece

`SinConexion` está diseñada y `drift` ya es dependencia, pero **no hay nada
implementado**. No es una pantalla más: implica

- guardar los movimientos localmente con su hora real,
- reintentar al recuperar señal,
- resolver conflictos (dos bodegueros despachando el mismo material sin red),
- y decidir qué operaciones **no** se permiten offline —
  aprobar una solicitud y congelar un presupuesto necesitan confirmar estado
  en el servidor.

> Conviene tratarla como una épica aparte, no como una pantalla del sprint.

### 6.2 Los coeficientes de cubicación son de referencia, no reales

`RecetaCubicacion.java` define cuánto material lleva cada m² por tipo de
partida. **Los valores actuales son orientativos**, puestos para que el motor
funcione. El diagrama de clases no modela una tabla de recetas, así que hubo
que inventarla.

**Acción requerida:** reemplazarlos por las tablas de rendimiento reales de la
constructora antes de que un presupuesto salga de estas cifras.

### 6.3 Seguridad — antes de cualquier despliegue

| Punto | Estado |
|---|---|
| Admin semilla con PIN `0000` | 🟢 La `V11` anula ese PIN; la clave inicial viene de `PRIMER_ADMIN_CLAVE` y la cuenta debe cambiarla en el primer ingreso (SEG3). `V2` salió de `db/migration` (MT1). La app muestra el cambio de clave obligatorio (SEG3) |
| `JWT_SECRET` con valor por defecto | 🟢 Sin valor por defecto: la API no arranca sin uno propio de 32 bytes o más (SEG1). Rotarlo en las instancias que ya corrieron con el antiguo |
| Contraseñas de PostgreSQL `postgres/postgres` | 🟢 Sin valor por defecto: vienen del `.env`; la API usa `checkinobra_app` (solo DML) y Flyway `checkinobra_migrador`; el puerto va solo en `127.0.0.1` (SEG6, MT0) |
| API por HTTP sin TLS | 🟠 La app en release exige `https://` y Android bloquea el tráfico en claro (SEG9); falta el proxy TLS del despliegue |
| Sesión sin renovación | 🟢 Token de 30 min con refresh rotado (SEG10); la app lo renueva sola |

### 6.4 Dependencias declaradas pero sin usar

`drift` y `fl_chart` están en `pubspec.yaml` pero no se importan en ningún archivo:
marcan funcionalidad que aún no existe —la base local de la cola sin conexión y los
gráficos de la desviación—. `mobile_scanner`, `intl`, `qr_flutter` y `file_picker` ya
se usan (escáner, formato es-CL, credencial QR e importación de planillas).

---

## 7. Orden de trabajo propuesto

Las etapas de agosto —el flujo de solicitudes, la bodega completa, el trabajador, la
administración y el flujo del jefe de terreno hasta el presupuesto— están hechas. Lo que
queda, en este orden:

1. `JefeDesviacion` (integrar `fl_chart`): cierra el flujo del jefe y el criterio de
   aceptación «la desviación se muestra en la app».
2. `JefeCuadrillas` y, con ella, el alta de trabajadores desde la gestión.
3. `JefeInicio` y el endpoint `GET /api/obras/{id}/resumen`.
4. `SinPermiso`.
5. Pruebas de integración de la app contra el backend real.
6. Cola sin conexión (§6.1), con los requisitos por empresa ya escritos.
7. Ícono de la app.

---

## 8. Para la entrega académica

Además del código:

- [ ] Completar los nombres del equipo en el `README.md`
- [ ] Manual de usuario por rol — los mockups de `docs/mockups/` sirven de base
- [ ] Documentar la decisión de las recetas de cubicación (§6.2) en el informe
- [ ] Evidencia de pruebas — hoy solo existe la verificación manual de esta bitácora
- [ ] Diagrama de despliegue — el de clases ya está en `docs/diagrams/`

---

## 9. Multi-tenant: una base por empresa (actualizado 2026-11-20)

Épica [#102](https://github.com/4lan17/Capstone_Check-In-Obra/issues/102). El detalle del diseño está
en [`docs/arquitectura/multitenant.html`](arquitectura/multitenant.html) y la operación en el README.

**Implementado en el backend (fases 0 a 4):** usuarios de base propios (MT0), catálogo (MT1), enrutador sin
base por defecto (MT2), Flyway por base (MT3), login que resuelve la empresa antes del token (MT4), pruebas
con dos bases reales (MT5), rol `PLATAFORMA` (MT6), alta de una constructora de punta a punta (MT7) y
suspensión y respaldo por base (MT8). Los PR están encadenados y se integran en ese orden.

**Pendiente:**

- **Fase 5, la app:** la sesión, la obra activa y la copia de la credencial ya se guardan por empresa y usuario
  (MT9, PR #126). La base local y la cola de sincronización por empresa (MT10 #113) quedan como requisitos de
  la épica de la cola sin conexión (documento `arquitectura/cola-offline-por-empresa.md`, PR #132),
  porque la cola no existe todavía.
- **El refresh token ya lo usa la app** (SEG10, PR #142): renueva el token de 30 minutos sola. Hay que integrarlo
  junto con el PR #141 del backend: uno sin el otro pide la clave cada media hora o recibe un token que no existe.
- **Operadores de plataforma:** no hay forma de crear más del primero (se crea con `PLATAFORMA_OPERADOR_*`) ni de
  cambiarles la clave; su token no tiene refresh.
- **Altas a medias:** un corte del proceso en medio del alta deja una empresa a medias; no hay un barrido que la
  detecte. Si una compensación falla, queda en el log y el resto se limpia a mano.
- **Secretos de las bases creadas por la API:** viven en el volumen `secretos`, que hay que respaldar junto con las
  bases; los scripts de respaldo no lo incluyen. Programar y cifrar los respaldos es de quien despliega.
- **Suspensión con varias instancias:** vale en la instancia que la recibe (hoy hay una).
- **Mejoras anotadas:** `REVOKE` de la API sobre `flyway_schema_history`; índice único parcial en
  `solicitudes_material` (hoy la unicidad de "una solicitud pendiente" la sostiene un bloqueo de fila);
  pedidos de herramientas con QR no validan la obra del trabajador al crearse; planes con topes (el plan existe
  en el catálogo pero no limita nada).
- **Las cifras de la app** se midieron el 2026-11-22 (§1); las de las secciones 4 y 5 son las de agosto salvo lo corregido.

