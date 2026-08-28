# Check-In-Obra

Sistema de cubicación, presupuesto e inventario para PYMEs de la construcción.
Proyecto capstone — DuocUC.

El problema que resuelve: en obras de tabiquería y cielos, el material se cubica
en planilla, se compra a ojo y el consumo real nunca se compara contra lo
presupuestado. Check-In-Obra cierra ese ciclo — cubica la partida, congela el
presupuesto, registra cada movimiento de bodega con QR y muestra la desviación
mientras la obra todavía está abierta.

---

## Índice

- [Stack](#stack)
- [Arquitectura](#arquitectura)
- [Estructura del repositorio](#estructura-del-repositorio)
- [Requisitos previos](#requisitos-previos)
- [Puesta en marcha](#puesta-en-marcha)
- [Comandos del día a día](#comandos-del-día-a-día)
- [API](#api)
- [Roles y permisos](#roles-y-permisos)
- [Base de datos](#base-de-datos)
- [App móvil](#app-móvil)
- [Documentación de diseño](#documentación-de-diseño)
- [Problemas frecuentes](#problemas-frecuentes)
- [Equipo](#equipo)

---

## Stack

### Backend
| Componente | Versión | Para qué |
|---|---|---|
| Java | 21 | Lenguaje |
| Spring Boot | 4.1.1 | Framework (Web MVC, Data JPA, Security, Validation, Mail) |
| PostgreSQL | 16 | Base de datos |
| Flyway | — | Migraciones versionadas del esquema |
| JJWT | 0.12.6 | Emisión y validación de JWT |
| springdoc-openapi | 2.8.6 | Swagger UI / OpenAPI 3 |
| Lombok | — | Reduce boilerplate en entidades |
| Maven Wrapper | — | Build sin instalar Maven |

### Mobile
| Componente | Versión | Para qué |
|---|---|---|
| Flutter | 3.47.1 (stable) | Framework, solo Android |
| `mobile_scanner` | ^7.4.0 | Escaneo de QR (material, herramienta, credencial) |
| `dio` | ^5.11.0 | Cliente HTTP contra la API |
| `flutter_riverpod` | ^2.6.1 | Manejo de estado |
| `drift` | ^2.34.3 | Base local (cola de movimientos sin conexión) |
| `flutter_secure_storage` | ^11.0.0 | Guardar el JWT y el PIN de forma segura |
| `fl_chart` | ^1.2.0 | Gráficos de desviación y consumo |
| `intl` | ^0.20.3 | Formato de fechas y montos en es-CL |

---

## Arquitectura

Monorepo con dos aplicaciones que se comunican por HTTP/JSON:

```
┌────────────────────┐         REST + JWT          ┌────────────────────┐
│   App Flutter      │ ──────────────────────────► │  API Spring Boot   │
│   (Android)        │ ◄────────────────────────── │  :8080 en Docker   │
└────────────────────┘                             └─────────┬──────────┘
                                                             │ JDBC
                                                   ┌─────────▼──────────┐
                                                   │   PostgreSQL 16    │
                                                   └────────────────────┘
```

### Paquetes de dominio del backend

Uno por módulo del diagrama de clases. La regla es que `control` puede depender
de los demás, pero nadie depende de `control`:

| Paquete | Contiene |
|---|---|
| `config` | `Empresa`, `Usuario`, `RolUsuario`, seguridad JWT, manejo de errores |
| `obra` | `Obra`, `Cuadrilla`, `Trabajador`, `EstadoObra` |
| `cubicacion` | `Material`, `ParametroMerma`, `Partida`, `ItemCubicado`, `MotorCubicacion` |
| `presupuesto` | `Presupuesto`, `PresupuestoItem`, `ComparadorPresupuesto`, `ReporteDesviacion` |
| `inventario` | `KardexMovimiento`, `Herramienta`, `PrestamoHerramienta`, `SolicitudHerramienta`, `SolicitudMaterial` |
| `control` | `Alerta`, `TipoAlerta` |

**Números actuales:** 9 enums · 17 entidades JPA · 17 repositorios · 17 servicios ·
16 controladores REST · 51 rutas.

Cada capa tiene una responsabilidad clara:
- **Entidad** — estado y transiciones propias (`Obra.cerrar()`, `Presupuesto.congelar()`)
- **Servicio** — orquestación y reglas que cruzan agregados (validar que la obra
  no tenga herramientas fuera antes de cerrarla)
- **Controlador** — HTTP, validación de entrada y autorización por rol

### Reglas de negocio que vale la pena conocer

- **El stock no es una columna.** Es la suma con signo de los `KardexMovimiento`
  (`RECEPCION` suma, `DESPACHO`/`CONSUMO` restan). No existe stock negativo: un
  despacho mayor al disponible se rechaza con `409`.
- **Una solicitud no mueve nada por sí sola.** El trabajador crea la solicitud;
  recién cuando el bodeguero la aprueba se genera el `PrestamoHerramienta` o el
  `KardexMovimiento` de despacho.
- **Un presupuesto congelado no se toca.** `BORRADOR → APROBADO → CONGELADO`.
  Congelado, los precios dejan de seguir al catálogo: cambiar el precio de un
  material no altera presupuestos ya congelados.
- **Una obra no se cierra con cabos sueltos.** `Obra.cerrar()` exige cero
  herramientas sin devolver y cero alertas sin resolver.

---

## Estructura del repositorio

```
checkinobra/
├── backend/                         API REST en Spring Boot
│   ├── src/main/java/cl/duocuc/checkinobra/
│   │   ├── config/                  Empresa, Usuario, JWT, seguridad
│   │   ├── obra/                    Obra, Cuadrilla, Trabajador
│   │   ├── cubicacion/              Material, Partida, MotorCubicacion
│   │   ├── presupuesto/             Presupuesto, ComparadorPresupuesto
│   │   ├── inventario/              Kardex, Herramientas, Solicitudes
│   │   └── control/                 Alertas
│   ├── src/main/resources/
│   │   ├── application.properties
│   │   └── db/migration/            Migraciones Flyway (V1, V2)
│   ├── Dockerfile                   Build multi-etapa (Maven → JRE Alpine)
│   ├── .env.example
│   └── pom.xml
│
├── mobile/                          App Flutter (Android)
│   ├── lib/
│   │   ├── core/{theme,network}/    Tema visual y cliente HTTP
│   │   ├── data/{api,local_db}/     Repositorios remotos y base local
│   │   ├── features/                auth · cubicacion · presupuesto ·
│   │   │                            inventario · solicitudes · admin
│   │   └── shared_widgets/
│   ├── android/
│   ├── .env.example
│   └── pubspec.yaml
│
├── docs/
│   ├── diagrams/                    Diagrama de clases MVP1 (PNG)
│   ├── design-system/               Paleta, tipografía, reglas UX
│   └── mockups/                     3 lienzos de pantallas (.dc.html)
│
├── scripts/                         Utilidades en Python (fuera de producción)
├── docker-compose.yml
└── .env.example
```

---

## Requisitos previos

| Herramienta | Versión | Obligatorio para |
|---|---|---|
| Git | cualquiera reciente | Todo |
| Docker Desktop | 4.x | Backend + base de datos |
| JDK | **21** | Compilar el backend fuera de Docker |
| Flutter SDK | **3.47.1+** (stable) | App móvil |
| Android Studio | 2026.1+ | SDK de Android, emulador y editor |
| WSL 2 | — | **Solo Windows** — lo exige Docker Desktop |

El proyecto funciona igual en **Ubuntu** y **Windows**. Donde los comandos
difieren, este README muestra ambos. Los de `docker compose`, `git`, `flutter`
y `dart` son idénticos en los dos sistemas.

**No hace falta instalar:**
- **Maven** — el repo trae `mvnw` (Maven Wrapper), que se descarga solo.
- **PostgreSQL** — corre dentro de Docker. Instalarlo en el sistema solo genera
  conflictos de puerto.

### Instalación — Ubuntu

```bash
# JDK 21
sudo apt install openjdk-21-jdk

# Flutter
sudo snap install flutter --classic

# Android Studio: descargar de developer.android.com/studio
# (el asistente instala el SDK, platform-tools y un emulador)
```

Después de instalar Android Studio, agregar a `~/.bashrc`:

```bash
export ANDROID_HOME=$HOME/Android/Sdk
export ANDROID_SDK_ROOT=$ANDROID_HOME
export PATH=$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin
```

Aplicar los cambios sin cerrar la terminal:

```bash
source ~/.bashrc
```

### Instalación — Windows

Docker Desktop en Windows necesita **WSL 2**. Si nunca lo instalaste, primero
(en PowerShell **como administrador**) y reiniciar:

```powershell
wsl --install
```

Después, todo lo demás con `winget` en una PowerShell normal:

```powershell
winget install EclipseAdoptium.Temurin.21.JDK
winget install Docker.DockerDesktop
winget install Google.AndroidStudio
winget install Git.Git
```

> Si `winget` no encuentra alguno, los identificadores cambian de vez en cuando.
> Las descargas oficiales siempre funcionan:
> [JDK 21](https://adoptium.net/temurin/releases/?version=21) ·
> [Docker Desktop](https://www.docker.com/products/docker-desktop/) ·
> [Android Studio](https://developer.android.com/studio)

**Flutter** conviene instalarlo manualmente para controlar la versión:

1. Descargar el ZIP estable desde [docs.flutter.dev/get-started/install/windows](https://docs.flutter.dev/get-started/install/windows)
2. Descomprimir en `C:\src\flutter` — **no** en `C:\Program Files`, porque esa
   ruta exige permisos elevados y rompe algunos comandos
3. Agregar `C:\src\flutter\bin` al `PATH`

Variables de entorno (PowerShell; `setx` las deja permanentes, así que hay que
**abrir una terminal nueva** para que tomen efecto):

```powershell
setx ANDROID_HOME "$env:LOCALAPPDATA\Android\Sdk"
setx ANDROID_SDK_ROOT "$env:LOCALAPPDATA\Android\Sdk"
setx PATH "$env:PATH;$env:LOCALAPPDATA\Android\Sdk\platform-tools;$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin;C:\src\flutter\bin"
```

También se pueden editar a mano en *Panel de control → Sistema → Configuración
avanzada → Variables de entorno*, que es menos propenso a errores si el `PATH`
ya está largo.

### Aceptar las licencias de Android

Igual en ambos sistemas, una sola vez por computador:

```bash
flutter doctor --android-licenses   # responder "y" a cada una
flutter doctor                      # Android toolchain debe quedar en [✓]
```

> `flutter doctor` marcará en rojo **Chrome** y —según el sistema— **Linux
> toolchain** o **Visual Studio**. Es esperado: el MVP1 es solo Android. No
> instales nada para resolver esos dos.

---

## Puesta en marcha

```bash
git clone https://github.com/1Bryvn/Check-In-Obra.git
cd Check-In-Obra
```

### 1. Backend + base de datos

```bash
docker compose up -d
```

La primera vez tarda varios minutos: compila la imagen y descarga PostgreSQL.
Flyway crea el esquema completo y carga el usuario semilla automáticamente.

Verificar que respondió:

```bash
# Ubuntu
curl http://localhost:8081/v3/api-docs

# Windows (PowerShell)
curl.exe http://localhost:8081/v3/api-docs
```

> En PowerShell, `curl` es un alias de `Invoke-WebRequest` y **no** acepta los
> mismos parámetros. Por eso hay que escribir `curl.exe` con la extensión.
> En `cmd.exe` basta con `curl`.

Y abrir Swagger UI en **http://localhost:8081/swagger-ui.html**

### 2. Primer login

La migración `V2` deja un administrador para poder entrar la primera vez:

| Campo | Valor |
|---|---|
| Correo | `admin@arauco-ltda.cl` |
| PIN | `0000` |

**Ubuntu**

```bash
curl -X POST http://localhost:8081/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@arauco-ltda.cl","pin":"0000"}'
```

**Windows (PowerShell)** — las comillas simples no sirven para el JSON, hay que
escapar las dobles:

```powershell
curl.exe -X POST http://localhost:8081/api/auth/login `
  -H "Content-Type: application/json" `
  -d '{\"email\":\"admin@arauco-ltda.cl\",\"pin\":\"0000\"}'
```

Devuelve un JWT que se manda en las llamadas siguientes como
`Authorization: Bearer <token>`.

> ⚠️ Ese PIN es solo para arrancar en local. Antes de cualquier despliegue real
> hay que cambiarlo con `PUT /api/usuarios/{id}/pin`.

### 3. App móvil

```bash
cd mobile

cp .env.example .env                        # Ubuntu
copy .env.example .env                      # Windows (cmd)
Copy-Item .env.example .env                 # Windows (PowerShell)

flutter pub get
flutter run
```

Con el celular conectado por USB (con depuración USB activada) o el emulador
abierto. Confirmar que Flutter lo ve con `flutter devices`.

> **En Windows, si el celular no aparece** en `flutter devices`, casi siempre
> falta el driver USB del fabricante. Instalar el
> [Google USB Driver](https://developer.android.com/studio/run/win-usb) desde
> Android Studio (SDK Manager → SDK Tools → *Google USB Driver*), o el driver
> propio de la marca del teléfono. En Ubuntu no hace falta driver.

#### Qué se ve al correrla

Por ahora la app abre en una **pantalla de verificación de conexión**. No es
una pantalla del producto: es una herramienta para el equipo que comprueba, de
una sola vez, que el teléfono llega hasta la base de datos.

Al tocar *Probar conexión* hace un login real contra `/api/auth/login` con el
usuario semilla y muestra:

- **En verde** — el rol, la empresa, el JWT recibido y la latencia. Eso
  significa que funcionan la red, la API, PostgreSQL y las migraciones.
- **En rojo** — la causa concreta y el comando para resolverla. Distingue entre
  firewall bloqueando, redes WiFi distintas, IP desactualizada en el `.env` y
  backend caído.

Es el punto de partida: las pantallas reales del MVP1 (acceso por rol,
cubicación, bodega, solicitudes) se construyen sobre esta base.

**Si la app dice "No se pudo alcanzar el servidor"**, revisa en este orden:

1. El backend está arriba — `docker compose ps`
2. El teléfono y el computador están en la **misma red WiFi**
3. La IP del `.env` es la actual — cambia cada vez que cambias de red

> Sobre el firewall: aunque UFW esté activo con política `DROP`, **normalmente
> no bloquea** los puertos publicados por Docker. Docker inserta sus propias
> reglas de iptables que se evalúan antes que las de UFW. Verificado en este
> proyecto: con UFW activo, el celular alcanzó `:8081` sin agregar ninguna regla.
> Si aun así no conecta, comprueba desde el propio teléfono antes de tocar el
> firewall:
>
> ```bash
> adb shell "curl -s -o /dev/null -w '%{http_code}' http://<IP-del-PC>:8081/v3/api-docs"
> ```
>
> Si eso devuelve `200`, el problema no es de red sino del `.env` de la app.

---

## Comandos del día a día

### Docker

```bash
docker compose up -d          # levantar en segundo plano
docker compose up             # levantar viendo los logs (Ctrl+C baja todo)
docker compose logs -f        # seguir los logs
docker compose logs backend   # solo el backend
docker compose ps             # estado de los servicios
docker compose down           # bajar, CONSERVANDO los datos
docker compose down -v        # bajar y BORRAR la base (empezar de cero)
docker compose build          # reconstruir la imagen tras cambiar código
```

Estos comandos son **idénticos en Ubuntu y Windows**.

> `docker compose` solo actúa sobre este proyecto. El `name: checkinobra` del
> compose etiqueta contenedores, red y volumen, así que nunca toca otros stacks
> que tengas corriendo.

### Backend sin Docker (desde el IDE)

Necesitas la base levantada (`docker compose up -d db`) y un `.env` con el
datasource apuntando a `localhost:5433`.

El Maven Wrapper cambia de nombre según el sistema:

**Ubuntu**

```bash
cd backend
./mvnw compile                  # compilar
./mvnw package -DskipTests      # generar el .jar
./mvnw spring-boot:run          # ejecutar
./mvnw test                     # pruebas
```

**Windows**

```powershell
cd backend
.\mvnw.cmd compile
.\mvnw.cmd package -DskipTests
.\mvnw.cmd spring-boot:run
.\mvnw.cmd test
```

> Ambos archivos ya vienen en el repo y `.gitattributes` fija sus finales de
> línea (`mvnw` en LF, `mvnw.cmd` en CRLF), así que funcionan sin importar la
> configuración de Git de cada quien.

### Mobile

```bash
cd mobile
flutter pub get                       # instalar dependencias
flutter analyze                       # análisis estático
flutter run                           # correr en el dispositivo
flutter build apk --debug             # APK de depuración
flutter build apk --release           # APK de release
dart run build_runner build           # generar código de Drift
flutter devices                       # ver dispositivos conectados
```

Estos comandos son **idénticos en Ubuntu y Windows**.

---

## API

Base: `http://localhost:8081` · Swagger: `/swagger-ui.html`

| Recurso | Ruta base |
|---|---|
| Autenticación | `/api/auth` |
| Empresas | `/api/empresas` |
| Usuarios | `/api/usuarios` |
| Obras | `/api/obras` |
| Cuadrillas | `/api/cuadrillas` |
| Trabajadores | `/api/trabajadores` |
| Materiales | `/api/materiales` |
| Parámetros de merma | `/api/materiales/{id}/merma` |
| Partidas y cubicación | `/api/partidas` |
| Presupuestos | `/api/presupuestos` |
| Kardex | `/api/kardex` |
| Herramientas | `/api/herramientas` |
| Préstamos | `/api/prestamos-herramienta` |
| Solicitudes de herramienta | `/api/solicitudes-herramienta` |
| Solicitudes de material | `/api/solicitudes-material` |
| Alertas | `/api/alertas` |

### Autenticación

Dos formas de entrar, ambas devuelven el mismo JWT:

- `POST /api/auth/login` — correo + PIN. Para admin, jefe de terreno y bodeguero.
- `POST /api/auth/login-pin` — id de usuario + PIN. Para el trabajador, cuyo
  teléfono ya lo tiene identificado (nadie escribe un correo con guantes puestos).

El token dura 8 horas y lleva el id, el rol y la empresa del usuario.

### Códigos de respuesta

| Código | Cuándo |
|---|---|
| `400` | Datos inválidos o credenciales incorrectas |
| `403` | Sin token, o el rol no autoriza esa acción |
| `404` | El recurso no existe |
| `409` | La operación choca con una regla de negocio (stock insuficiente, presupuesto ya congelado, obra con herramientas fuera) |

---

## Roles y permisos

Una sola clase `Usuario` para los cuatro roles. Lo que cambia entre uno y otro
es `Usuario.rol`, y con eso el backend decide qué autoriza (`@PreAuthorize`).

| Acción | Trabajador | Bodeguero | Jefe terreno | Admin |
|---|:---:|:---:|:---:|:---:|
| Solicitar herramienta o material | ✅ | — | — | — |
| Mostrar credencial QR | ✅ | — | — | — |
| Aprobar o rechazar solicitudes | — | ✅ | — | ✅ |
| Recepción, despacho y consumo | — | ✅ | — | ✅ |
| Autorizar préstamo y devolución | — | ✅ | — | ✅ |
| Cerrar turno de bodega | — | ✅ | — | ✅ |
| Cubicar partidas | — | — | ✅ | ✅ |
| Congelar presupuesto | — | — | ✅ | ✅ |
| Resolver alertas | — | ✅ | ✅ | ✅ |
| Crear usuarios y asignar rol | — | — | — | ✅ |
| Catálogo, precios y mermas | — | — | — | ✅ |
| Crear y cerrar obras | — | — | — | ✅ |

---

## Base de datos

### Puertos

| Servicio | Host | Dentro de Docker |
|---|---|---|
| Backend (API + Swagger) | `8081` | `8080` |
| PostgreSQL | `5433` | `5432` |

Se usan 8081 y 5433 en el host —no los 8080/5432 habituales— porque esos puertos
suelen estar ocupados por otros proyectos. Entre contenedores la comunicación
sigue siendo `db:5432`, así que la aplicación no se entera del cambio.

### Conectarse con un cliente SQL

| Campo | Valor |
|---|---|
| Host | `localhost` |
| Puerto | `5433` |
| Base | `checkinobra` |
| Usuario | `postgres` |
| Contraseña | `postgres` |

O por terminal:

```bash
docker compose exec db psql -U postgres -d checkinobra
```

### Migraciones

El esquema lo maneja **Flyway**, no Hibernate (`ddl-auto=validate`: Hibernate
solo verifica que las entidades calcen con las tablas).

| Archivo | Qué hace |
|---|---|
| `V1__init_schema.sql` | Crea las 17 tablas con sus llaves foráneas e índices |
| `V2__seed_admin.sql` | Inserta una empresa y el admin de arranque |

**Para cambiar el esquema** se crea un archivo nuevo (`V3__...sql`). Nunca se
edita una migración ya aplicada: Flyway guarda un hash de cada una y falla si
detecta que cambió.

---

## App móvil

### Emulador (teléfono virtual)

Para trabajar sin el celular a mano. El repo asume un AVD llamado
`Check-In-Obra_Pixel5`, con perfil **Pixel 5** y **Android 13 (API 33)** — la
misma versión que los teléfonos de prueba del equipo, así lo que funciona en
uno funciona en el otro.

**Crearlo** (una vez por computador):

```bash
# 1. Imagen de sistema — ~8 GB en disco, la descarga tarda varios minutos
sdkmanager "system-images;android-33;google_apis;x86_64"

# 2. Crear el dispositivo virtual
avdmanager create avd \
  --name Check-In-Obra_Pixel5 \
  --package "system-images;android-33;google_apis;x86_64" \
  --device "pixel_5"
```

**Ajustes recomendados** en `~/.android/avd/Check-In-Obra_Pixel5.avd/config.ini`
(en Windows: `%USERPROFILE%\.android\avd\...`):

```ini
hw.camera.back=webcam0   # usa la webcam real → permite probar el escaneo QR
hw.camera.front=emulated
hw.keyboard=yes          # escribir con el teclado del computador
hw.gpu.enabled=yes       # sin esto la UI de Flutter va a tirones
hw.gpu.mode=host
```

**Arrancarlo:**

```bash
emulator -avd Check-In-Obra_Pixel5 &
flutter devices                       # debe aparecer emulator-5554
flutter run -d emulator-5554
```

También se puede lanzar desde Android Studio: *Device Manager* → ▶ junto al AVD.

> **Aceleración por hardware.** El emulador necesita KVM (Linux) o WHPX
> (Windows) para no ir lentísimo. Comprobar con:
>
> ```bash
> emulator -accel-check
> ```
>
> En Ubuntu suele funcionar sin configurar nada: `systemd-logind` da acceso a
> `/dev/kvm` por ACL al usuario de la sesión. Si dice que no está disponible,
> ahí sí hace falta `sudo usermod -aG kvm $USER` y volver a iniciar sesión.

> **La misma URL sirve para ambos.** Desde el emulador funcionan tanto
> `10.0.2.2:8081` como la IP del computador en la WiFi. Comprobado: el mismo
> APK, con `API_BASE_URL=http://192.168.1.29:8081`, conectó igual en el celular
> físico (355 ms) y en el emulador (856 ms). No hace falta recompilar al
> cambiar de dispositivo.

### Configurar la URL de la API

```bash
cd mobile
cp .env.example .env
```

El valor depende de dónde pruebes:

| Escenario | `API_BASE_URL` |
|---|---|
| Emulador de Android | `http://10.0.2.2:8081` |
| Celular físico por USB | `http://<IP-de-tu-PC>:8081` |

`10.0.2.2` es la dirección con que el emulador alcanza el `localhost` del
computador. En un celular físico hay que usar la IP real del PC en la WiFi, y
ambos deben estar conectados a la misma red.

Para averiguar esa IP:

```bash
hostname -I            # Ubuntu
ipconfig               # Windows — buscar "Dirección IPv4" del adaptador WiFi
```

### Detalle de configuración

`compileSdk` está fijado en **37** en `android/app/build.gradle.kts`, en vez de
heredar el 36 que entrega Flutter. La razón es que `flutter_secure_storage`
exige compilar contra 37 y el build falla sin eso. Es retrocompatible: no afecta
`targetSdk` (comportamiento en runtime) ni `minSdk` (dispositivos soportados).

---

## Documentación de diseño

En `docs/`:

- **`diagrams/`** — Diagrama de clases del MVP1. Es la fuente de verdad del
  modelo: entidades, enums y relaciones del backend salen de ahí.
- **`design-system/`** — Paleta, tipografía (Fira Sans + Fira Code), estilo e
  íconos, con las reglas UX que aplican en terreno.
- **`mockups/`** — Tres lienzos con las pantallas diseñadas. `design-movil/`
  es el más completo: 34 pantallas de teléfono organizadas por rol, más un mapa
  de navegación y la matriz de permisos.

Los `.dc.html` se abren directamente en el navegador.

### Estado del proyecto

**[`docs/PENDIENTES.md`](docs/PENDIENTES.md)** — qué está hecho, qué falta, en
qué orden conviene atacarlo y qué riesgos hay abiertos. Es el documento a
revisar antes de tomar una tarea.

---

## Problemas frecuentes

**El puerto 8081 o 5433 ya está en uso**

```bash
# Ubuntu
ss -ltnp | grep -E ':8081|:5433'

# Windows (PowerShell)
netstat -ano | findstr ":8081 :5433"
# el último número es el PID; para ver qué proceso es:
tasklist /FI "PID eq <PID>"
```

Si es otro contenedor, bájalo. Si necesitas otros puertos, cambia el lado
izquierdo del mapeo en `docker-compose.yml` (`"8082:8080"`) y actualiza
`mobile/.env`.

---

**`flutter doctor` marca Chrome y Linux toolchain en rojo**

Es esperado y no afecta nada: el MVP1 es solo Android. No instales clang, CMake
ni ninja para eso.

---

**`flutter doctor --android-licenses` dice "The --licenses option is no longer needed"**

Pasa con `cmdline-tools` 23.0 o superior: Google eliminó ahí el comando, pero
Flutter todavía lo usa para verificar. La solución es dejar la versión **22.0**
como `latest` (es la última con el `sdkmanager` clásico), conservando la nueva
en su propia carpeta versionada.

**Ubuntu**

```bash
cd ~/Android/Sdk/cmdline-tools
mv latest 23.0
curl -L -o ct.zip https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip
unzip -q ct.zip && mv cmdline-tools latest && rm ct.zip
flutter doctor --android-licenses
```

**Windows (PowerShell)**

```powershell
cd "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools"
Rename-Item latest 23.0
Invoke-WebRequest -Uri "https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip" -OutFile ct.zip
Expand-Archive ct.zip -DestinationPath .
Rename-Item cmdline-tools latest
Remove-Item ct.zip
flutter doctor --android-licenses
```

---

**El build de Android falla pidiendo `compileSdk 37`**

Verifica que `mobile/android/app/build.gradle.kts` tenga `compileSdk = 37` y que
tengas la plataforma instalada (Android Studio → SDK Manager → SDK Platforms).

---

**El backend no levanta: "Connection refused" contra la base**

El `docker-compose.yml` ya tiene un `healthcheck` que hace esperar al backend.
Si igual falla, revisa los logs de la base:

```bash
docker compose logs db
```

---

**Quiero empezar de cero con la base de datos**

```bash
docker compose down -v && docker compose up -d
```

Borra el volumen y Flyway vuelve a crear el esquema y el usuario semilla.

---

**Cambié código del backend y no se refleja**

La imagen hay que reconstruirla:

```bash
docker compose up -d --build
```

---

**(Windows) `docker compose` falla con "docker daemon is not running"**

Docker Desktop tiene que estar **abierto** — no basta con tenerlo instalado.
Ábrelo desde el menú Inicio y espera a que el ícono de la barra de tareas quede
en verde. Si además da un error de WSL, ejecutar en PowerShell como
administrador:

```powershell
wsl --update
```

---

**(Windows) `flutter` o `mvnw.cmd` no se reconocen como comando**

El `PATH` no tomó los cambios. Abre una terminal **nueva** — `setx` no afecta a
las ventanas ya abiertas. Si sigue igual, verifica que la ruta esté registrada:

```powershell
$env:PATH -split ';' | Select-String "flutter"
```

---

## Equipo

| Integrante | Área |
|---|---|
| [nombre] | Backend |
| [nombre] | Mobile |
| [nombre] | Backend / Inventario |
