<#
Deja Check-In-Obra andando para desarrollar en Windows: enciende Docker
Desktop si esta apagado, construye y levanta las imagenes, y arranca un
emulador de Android. El emulador parte primero y bootea mientras Docker
construye, que es lo que mas tarda.

  powershell -ExecutionPolicy Bypass -File scripts\levantar.ps1
  powershell -ExecutionPolicy Bypass -File scripts\levantar.ps1 -App          # ademas corre la app (flutter run)
  powershell -ExecutionPolicy Bypass -File scripts\levantar.ps1 -SinCache     # reconstruye las imagenes desde cero
  powershell -ExecutionPolicy Bypass -File scripts\levantar.ps1 -SinEmulador  # solo Docker
  powershell -ExecutionPolicy Bypass -File scripts\levantar.ps1 -Avd NOMBRE   # otro emulador

En Linux y macOS usar scripts/levantar.sh. Compatible con Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [switch]$App,
    [switch]$SinCache,
    [switch]$SinEmulador,
    [string]$Avd = $env:AVD
)

# 'Continue' y no 'Stop': en Windows PowerShell 5.1, con 'Stop' cualquier linea
# que adb, emulator o docker escriban en stderr corta el script aunque el
# comando haya funcionado. Los codigos de salida se revisan a mano.
$ErrorActionPreference = 'Continue'

$Raiz = Split-Path -Parent $PSScriptRoot
Set-Location $Raiz

$Api = 'http://localhost:8081'
# El backend no tiene actuator; que publique su OpenAPI significa que arranco
# y que Flyway ya corrio.
$Sonda = "$Api/v3/api-docs"
$EsperaDocker = 180
$EsperaApi = 240        # la primera vez compila la imagen entera
$EsperaEmulador = 240
$PuertoEmulador = 5554
$Dispositivo = "emulator-$PuertoEmulador"

function Paso($texto) { Write-Host ''; Write-Host $texto -ForegroundColor Cyan }
function Info($texto) { Write-Host "  $texto" }
function Bien($texto) { Write-Host "  $texto" -ForegroundColor Green }
function Mal($texto)  { Write-Host "  $texto" -ForegroundColor Red }
function Salir($texto) { Mal $texto; exit 1 }

if ($App -and $SinEmulador) {
    Salir '-App necesita el emulador: no se puede combinar con -SinEmulador.'
}

# --- herramientas ---------------------------------------------------------
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Salir "Falta 'docker' en el PATH. Instala Docker Desktop."
}

# emulator.exe y adb.exe suelen no estar en el PATH aunque el SDK este
# instalado: Android Studio no los agrega. Se buscan en las rutas de siempre.
$Emulator = $null
$Adb = $null
if (-not $SinEmulador) {
    $candidatos = @(@($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk')) |
        Where-Object { $_ -and (Test-Path (Join-Path $_ 'emulator\emulator.exe')) })
    $comando = Get-Command emulator -ErrorAction SilentlyContinue
    if ($comando) {
        $Emulator = $comando.Source
    } elseif ($candidatos) {
        $Emulator = Join-Path $candidatos[0] 'emulator\emulator.exe'
    }
    $comando = Get-Command adb -ErrorAction SilentlyContinue
    if ($comando) {
        $Adb = $comando.Source
    } elseif ($candidatos) {
        $Adb = Join-Path $candidatos[0] 'platform-tools\adb.exe'
    }
    if (-not $Emulator -or -not (Test-Path $Emulator) -or -not $Adb -or -not (Test-Path $Adb)) {
        Mal 'No se encontro el SDK de Android (emulator.exe y adb.exe).'
        Info 'Instalalo desde Android Studio o define ANDROID_HOME.'
        Info 'Para seguir solo con Docker: scripts\levantar.ps1 -SinEmulador'
        exit 1
    }
    if ($App -and -not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        Salir "Falta 'flutter' en el PATH."
    }
}

function EmuladorCorriendo {
    $lineas = & $Adb devices 2>$null
    return [bool]($lineas | Where-Object { $_ -match "^$Dispositivo\s" })
}

# --- 1. emulador (en segundo plano) ----------------------------------------
if (-not $SinEmulador) {
    Paso 'Emulador'
    & $Adb start-server 2>$null | Out-Null
    if (EmuladorCorriendo) {
        Bien "$Dispositivo ya estaba corriendo."
    } else {
        $disponibles = @(& $Emulator -list-avds 2>$null | Where-Object { $_ -and $_ -notmatch '^INFO' })
        if ($disponibles.Count -eq 0) {
            Mal 'No hay ningun emulador creado.'
            Info "Crea uno en Android Studio (Device Manager) o con 'flutter emulators --create'."
            exit 1
        }
        if ($Avd) {
            if ($disponibles -notcontains $Avd) {
                Mal "No existe el emulador '$Avd'. Los disponibles son:"
                $disponibles | ForEach-Object { Info "  $_" }
                exit 1
            }
        } elseif ($disponibles -contains 'Check-In-Obra_Pixel5') {
            $Avd = 'Check-In-Obra_Pixel5'
        } else {
            $Avd = $disponibles[0]
        }
        Info "Arrancando $Avd; bootea mientras se levanta Docker."
        # Proceso propio: sigue vivo cuando el script termina. Abre ademas una
        # consola con el log del emulador; cerrarla apaga el emulador.
        Start-Process -FilePath $Emulator -WindowStyle Minimized `
            -ArgumentList @('-avd', $Avd, '-port', $PuertoEmulador, '-netdelay', 'none', '-netspeed', 'full') | Out-Null
    }
}

# --- 2. Docker Desktop -----------------------------------------------------
function DockerResponde {
    & docker info *> $null
    return ($LASTEXITCODE -eq 0)
}

Paso 'Docker Desktop'
if (DockerResponde) {
    Bien 'Ya estaba encendido.'
} else {
    $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (-not (Test-Path $desktop)) {
        Salir "Docker no responde y no se encontro Docker Desktop en '$desktop'."
    }
    Info 'Encendiendo Docker Desktop...'
    Start-Process -FilePath $desktop | Out-Null
    $limite = (Get-Date).AddSeconds($EsperaDocker)
    while (-not (DockerResponde)) {
        if ((Get-Date) -gt $limite) {
            Salir "Docker Desktop no respondio en ${EsperaDocker}s. Revisa que WSL 2 este instalado y actualizado."
        }
        Start-Sleep -Seconds 3
    }
    Bien 'Docker Desktop responde.'
}

# --- 3. imagenes y contenedores --------------------------------------------
Paso 'Construyendo las imagenes'
if ($SinCache) { & docker compose build --no-cache } else { & docker compose build }
if ($LASTEXITCODE -ne 0) { Salir 'Fallo la construccion de las imagenes.' }

Paso 'Levantando los contenedores'
& docker compose up -d
if ($LASTEXITCODE -ne 0) { Salir 'No se pudieron levantar los contenedores.' }

function ApiResponde {
    try {
        $r = Invoke-WebRequest -Uri $Sonda -UseBasicParsing -TimeoutSec 5
        return ($r.StatusCode -eq 200)
    } catch {
        return $false
    }
}

Paso 'Esperando que la API responda'
$limite = (Get-Date).AddSeconds($EsperaApi)
while (-not (ApiResponde)) {
    if ((Get-Date) -gt $limite) {
        Mal "La API no respondio en ${EsperaApi}s. Ultimas lineas del backend:"
        & docker compose logs --tail=30 backend
        exit 1
    }
    Start-Sleep -Seconds 2
}
Bien "La API responde en $Api"

# --- 4. esperar el emulador ------------------------------------------------
if (-not $SinEmulador) {
    Paso 'Esperando que el emulador termine de bootear'
    $limite = (Get-Date).AddSeconds($EsperaEmulador)
    while ($true) {
        $booteado = (& $Adb -s $Dispositivo shell getprop sys.boot_completed 2>$null | Out-String).Trim()
        if ($booteado -eq '1') { break }
        if ((Get-Date) -gt $limite) {
            Mal "$Dispositivo no termino de bootear en ${EsperaEmulador}s."
            Info "Revisa la consola del emulador. Si falta aceleracion por hardware, activa 'Plataforma del hipervisor de Windows'."
            exit 1
        }
        Start-Sleep -Seconds 2
    }
    Bien "$Dispositivo listo."
}

# La app lee la URL de la API de mobile\.env. Sin ese archivo igual arranca,
# pero conviene que exista para que quien lo edite sepa donde esta.
$envMovil = Join-Path $Raiz 'mobile\.env'
if (-not (Test-Path $envMovil)) {
    Copy-Item (Join-Path $Raiz 'mobile\.env.example') $envMovil
    Info 'Creado mobile\.env desde .env.example (API_BASE_URL=http://10.0.2.2:8081).'
}

# --- resumen ---------------------------------------------------------------
Paso 'Listo'
Info "API          $Api"
Info "Swagger      $Api/swagger-ui.html"
Info 'PostgreSQL   localhost:5433  (postgres / postgres)'
Info 'Admin        admin@arauco-ltda.cl  PIN 0000'
if (-not $SinEmulador) { Info "Emulador     $Dispositivo" }
Info 'Cuentas de los cuatro roles: py scripts\cuentas_de_prueba.py'
Info 'Bajar todo:                  docker compose down'

if ($App) {
    Paso "Corriendo la app en $Dispositivo"
    Set-Location (Join-Path $Raiz 'mobile')
    & flutter pub get
    & flutter run -d $Dispositivo
} elseif (-not $SinEmulador) {
    Info "Correr la app:               cd mobile; flutter run -d $Dispositivo"
}
