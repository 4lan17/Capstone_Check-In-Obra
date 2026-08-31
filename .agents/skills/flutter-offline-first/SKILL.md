---
name: flutter-offline-first
description: Construir o modificar la cola de movimientos sin conexión de la app Flutter de Check-In-Obra (drift + dio + riverpod). Usar al trabajar en escaneo QR, recepción, despacho, consumo, préstamos, sincronización, o cualquier pantalla que registre algo estando en terreno sin señal.
---

# Cola de movimientos sin conexión

## Por qué existe

La bodega de una obra está en un container de lata, en un subterráneo o en un
cerro. No hay señal, y aún así el material sale igual. Si la app exige red para
registrar un despacho, el bodeguero anota en un papel y transcribe al final del
día — que es exactamente la planilla que este proyecto vino a eliminar.

De ahí la regla que ordena todo lo demás:

> **Registrar nunca falla por falta de red.** La operación se guarda local, se
> confirma en pantalla, y se sincroniza sola cuando vuelve la señal.

## Estado actual

`drift ^2.34.3`, `drift_dev` y `build_runner` ya están en `pubspec.yaml`, pero
**todavía no hay ni una línea de drift escrita**: hoy todo va directo contra la
API y un despacho sin señal simplemente falla. Esta skill define cómo construir
la cola, no cómo se construyó.

La estructura vigente, para saber dónde encaja:

```
lib/core/           red (ApiClient, errores), tema, formato es-CL, storage seguro
lib/core/db/        ← acá va la base drift: tablas, DAO, el .g.dart generado
lib/data/modelos/   Obra, MaterialObra, MovimientoKardex, Herramienta, Alerta…
lib/data/api/       ClienteRest + las APIs del dominio, con sus providers
lib/data/cola/      ← acá van el repositorio de la cola y el sincronizador
lib/features/bodega/    shell del bodeguero: es quien encola
lib/features/admin/     shell del administrador: no encola nada
```

El punto de entrada es `KardexApi.registrar`, en `data/api/dominio_api.dart`:
hoy hace un POST y propaga el fallo. La cola se interpone ahí, no en la
pantalla — `PantallaMovimiento` no debería enterarse de si hubo red.

## Qué se encola y qué no

| Encolar | Nunca encolar |
|---|---|
| Recepción, despacho, consumo | Login y acceso por PIN |
| Préstamo y devolución de herramienta | Cualquier lectura (stock, catálogo, alertas) |
| Solicitudes de material y herramienta | Congelar presupuesto |
| Cierre de turno de bodega | Crear o cerrar obra |

El criterio: se encola lo que **agrega un hecho** que ocurrió físicamente en la
obra y que el trabajador presenció. No se encola nada que requiera una decisión
del servidor, porque diferirla es prometer algo que no se puede cumplir.

## La tabla

```dart
class MovimientosPendientes extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Clave de idempotencia. Se genera en el teléfono al encolar y viaja al
  /// servidor: si la respuesta se pierde y se reintenta, el backend reconoce
  /// que ya lo grabó en vez de duplicar el movimiento.
  TextColumn get idempotencyKey => text().unique()();

  TextColumn get tipo => text();          // RECEPCION | DESPACHO | CONSUMO
  IntColumn get obraId => integer()();
  IntColumn get materialId => integer()();
  RealColumn get cantidad => real()();

  /// Momento real del hecho en la obra, no el de la sincronización.
  DateTimeColumn get ocurridoEn => dateTime()();

  TextColumn get estado => text();        // ver la máquina de estados
  IntColumn get intentos => integer().withDefault(const Constant(0))();
  TextColumn get ultimoError => text().nullable()();
}
```

### Máquina de estados

```
PENDIENTE ──envío ok──────────► SINCRONIZADO   (se puede purgar a los 7 días)
    │
    ├──error de red (timeout, sin conexión)──► PENDIENTE, intentos++
    │
    └──rechazo del servidor (4xx)────────────► RECHAZADO   (nunca se reintenta)
```

Esa separación es lo único que hace que la cola sea confiable. Los dos casos se
ven igual desde `dio` y significan cosas opuestas:

- **Fallo de red** — el hecho sigue siendo válido, el servidor no se enteró.
  Reintentar es correcto.
- **Rechazo del servidor** — 409 por stock insuficiente, 404 porque borraron el
  material, 403 porque cambió el rol. Reintentar no lo va a arreglar nunca. El
  movimiento queda `RECHAZADO` y **hay que mostrárselo a quien lo registró**,
  porque en la obra el material ya salió y ahora hay un descuadre físico que
  alguien tiene que resolver a mano.

Tragarse un rechazo en silencio es el peor bug posible en esta app: el kardex
queda mintiendo y nadie se entera. Ver [[kardex-invariantes]].

`ApiClient` está configurado con `validateStatus: (s) => s != null && s < 500`,
así que los 4xx **no** lanzan `DioException`: llegan como respuesta normal. Al
escribir el sincronizador, discrimina por `response.statusCode`, no por si hubo
excepción.

## El sincronizador

```dart
Future<void> sincronizar() async {
  final pendientes = await _dao.pendientes();   // ordenadas por ocurridoEn
  for (final m in pendientes) {
    // Secuencial, no Future.wait: el servidor valida el stock contra el saldo
    // acumulado, y en paralelo dos despachos del mismo material se pisan.
    await _enviar(m);
  }
}
```

Reglas:

- **Secuencial y en orden de `ocurridoEn`.** El backend valida stock contra el
  saldo del momento; reordenar la cola cambia qué movimiento pasa y cuál choca.
- **Backoff con techo.** `intentos` crece y el reintento se espacia. Un
  reintento cada segundo contra un servidor caído gasta la batería del teléfono,
  que en obra no se recarga hasta la noche.
- **Idempotente.** El `idempotencyKey` viaja en cada envío. Que el backend
  todavía no lo honre no es razón para no mandarlo: genera la clave y deja el
  hueco documentado.
- **Sin trabajo en background.** No hay `workmanager` en el proyecto. La
  sincronización corre al abrir la app, al volver del segundo plano y al tocar
  "reintentar". No prometas en la UI una sincronización que el sistema no va a
  ejecutar con la app cerrada.

## Lo que la pantalla tiene que mostrar

Una cola invisible es una cola en la que nadie confía. El bodeguero necesita
saber, sin preguntar, si lo que registró llegó.

- **Confirmación inmediata al encolar**, con la palabra correcta: "Registrado —
  se envía al recuperar señal", no "Guardado" a secas. El texto tiene que
  distinguir entre estar en el teléfono y estar en el servidor.
- **Contador de pendientes siempre visible** mientras haya algo en cola.
- **Los rechazados se muestran aparte y no se pueden ignorar**: qué movimiento,
  qué material, qué dijo el servidor, y qué hacer al respecto.
- **Nunca un spinner bloqueante** para encolar. La escritura local es
  instantánea; un spinner ahí solo enseña a desconfiar de la app.
- Anuncia el cambio de estado a los lectores de pantalla con
  `Semantics(liveRegion: true)` — el contador que cambia de 3 a 2 sin decir nada
  no existe para quien no lo ve.

Los mensajes de error de red ya están traducidos a lenguaje de obra en
`core/network/errores.dart` (`mensajeDeError`). Úsalo, no armes strings nuevos.

## Riverpod

Sigue lo que ya hay en `core/network/api_client.dart`: `Provider` para las
dependencias sin estado, `AsyncNotifier` para el estado con carga, como
`SesionController`.

```dart
final baseDatosProvider = Provider<AppDatabase>((ref) => AppDatabase());
final colaDaoProvider   = Provider((ref) => ref.watch(baseDatosProvider).colaDao);

/// Stream: la UI reacciona sola cuando cambia la cola, sin refrescos a mano.
final pendientesProvider = StreamProvider<List<MovimientoPendiente>>(
  (ref) => ref.watch(colaDaoProvider).observarPendientes(),
);
```

Usa `watch` para lo que se re-renderiza y `read` dentro de callbacks, tal como
está hecho en `SesionController`.

## Seguridad

`flutter_secure_storage` es para el JWT y solo para el JWT. La base drift **no
está cifrada**: no guardes en ella tokens, el PIN, ni datos personales del
trabajador más allá del id. Un movimiento de kardex en claro es aceptable; una
credencial no.

## Después de generar código

```bash
cd mobile
dart run build_runner build --delete-conflicting-outputs
dart format .
flutter analyze
flutter test
```

El `.g.dart` de drift se versiona. `dart format` no es opcional: la CI de
`.github/workflows/ci.yml` verifica el formato.

## Checklist

- [ ] Encolar responde al instante y no puede fallar por red
- [ ] Fallo de red y rechazo del servidor son ramas distintas del código
- [ ] Un `RECHAZADO` termina en pantalla, no en un log
- [ ] El envío es secuencial y ordenado por `ocurridoEn`
- [ ] Cada movimiento lleva `idempotencyKey`
- [ ] El reintento tiene backoff con techo
- [ ] El contador de pendientes se ve mientras haya cola
- [ ] `ocurridoEn` guarda el momento del hecho, no el del envío
- [ ] Nada sensible en la base drift
- [ ] `build_runner`, `dart format`, `flutter analyze` y `flutter test` pasan
