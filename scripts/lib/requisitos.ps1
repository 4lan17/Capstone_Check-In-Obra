<#
Requisitos de Check-In-Obra en Windows: detecta lo que falta y lo instala solo.
Lo carga scripts\levantar.ps1 con '.'; no se ejecuta suelto. Compatible con Windows PowerShell 5.1.

Instala con winget (Git, JDK 21, Docker Desktop) y con descargas verificadas por sha256 (Flutter, las
herramientas de linea de comandos de Android). WSL 2 y el hipervisor los exige Docker Desktop / el
emulador y necesitan un paso elevado y REINICIAR Windows: el script se detiene ahi y lo dice.

Que se pide depende del modo (variables de levantar.ps1):
  -SinEmulador   solo Docker (y Git)
  -Telefono      + Flutter, JDK y el SDK de Android (sin emulador)
  (por defecto)  + emulador, imagen del sistema y el AVD Check-In-Obra_Pixel5

Es idempotente: con todo instalado no descarga ni instala nada.
#>

# --- versiones fijadas ---------------------------------------------------------------------------
# Mantener igual que .github/workflows/ci.yml (flutter-version), mobile/android/app/build.gradle.kts
# (compileSdk) y scripts/lib/requisitos.sh.
$ReqFlutterVersion = '3.47.1'
$ReqFlutterSha256 = '4cbf94fde1f5f8d6b9fc50b2483b57cf2077f61712282c2f4cf92560168f442b'
$ReqFlutterUrl = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_$ReqFlutterVersion-stable.zip"
$ReqCmdlineBuild = '15859902'
$ReqCmdlineSha256 = '90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a'
$ReqCmdlineUrl = "https://dl.google.com/android/repository/commandlinetools-win-${ReqCmdlineBuild}_latest.zip"
$ReqPlataforma = 'platforms;android-37.0'
$ReqBuildTools = 'build-tools;36.0.0'
$ReqImagen = 'system-images;android-33;google_apis;x86_64'
$ReqAvdDefecto = 'Check-In-Obra_Pixel5'
$ReqJavaMinimo = 17
$ReqFlutterDir = 'C:\src\flutter'     # no en Program Files: esa ruta exige permisos elevados
$ReqWingetYaInstalado = -1978335189  # 0x8A15002B: ya esta y no hay nada que actualizar

$script:ReqFalta = @()
$script:ReqAvisos = @()
$script:ReqInstalado = $false
$script:ReqReiniciar = $false

# --- utilidades -----------------------------------------------------------------------------------
function Req-Tiene([string]$Nombre) { return [bool](Get-Command $Nombre -ErrorAction SilentlyContinue) }

# Req-VersionGe '3.50.1' '3.47.1' -> $true. Compara numeros, no texto.
function Req-VersionGe([string]$A, [string]$B) { return ([version]$A) -ge ([version]$B) }

function Req-Falta([string]$Id) { $script:ReqFalta += $Id }
function Req-EnFalta([string]$Id) { return ($script:ReqFalta -contains $Id) }

function Req-QuiereFlutter { return ((-not $SinEmulador) -or $Telefono) }
function Req-QuiereEmulador { return (-not $SinEmulador) }

function Req-Nombre([string]$Id) {
    switch ($Id) {
        'git'          { return 'Git' }
        'jdk'          { return "JDK $ReqJavaMinimo o superior" }
        'wsl'          { return 'WSL 2 (lo exige Docker Desktop)' }
        'docker'       { return 'Docker Desktop' }
        'flutter'      { return "Flutter $ReqFlutterVersion o superior" }
        'sdk-cmdline'  { return 'Herramientas de linea de comandos de Android' }
        'sdk-paquetes' { return 'SDK de Android (plataforma, build-tools, platform-tools, licencias)' }
        'emulador'     { return 'Emulador de Android' }
        'imagen'       { return 'Imagen del sistema del emulador (Android 13)' }
        'avd'          { return "Emulador $ReqAvdDefecto" }
        'hipervisor'   { return 'Aceleracion del emulador (Plataforma del hipervisor de Windows)' }
        default        { return $Id }
    }
}

# Tamano aproximado de la descarga, en MB.
function Req-Mb([string]$Id) {
    switch ($Id) {
        'git'          { return 60 }
        'jdk'          { return 200 }
        'wsl'          { return 100 }
        'docker'       { return 600 }
        'flutter'      { return 1900 }
        'sdk-cmdline'  { return 180 }
        'sdk-paquetes' { return 250 }
        'emulador'     { return 350 }
        'imagen'       { return 1300 }
        default        { return 0 }
    }
}

# --- detectar ---------------------------------------------------------------------------------------
# Version mayor a partir de la primera linea de 'java -version' / 'javac -version'.
function Req-JavaMayor([string]$Linea) {
    $v = ''
    if ($Linea -match '"([^"]+)"') { $v = $Matches[1] }
    elseif ($Linea -match '^\S+\s+(\S+)') { $v = $Matches[1] }
    if ($v -like '1.*') { $v = $v.Substring(2) }
    if ($v -match '^(\d+)') { return [int]$Matches[1] }
    return 0
}

function Req-JavacMayor([string]$Javac) {
    $linea = (& $Javac -version 2>&1 | Select-Object -First 1 | Out-String).Trim()
    return (Req-JavaMayor $linea)
}

# Deja JAVA_HOME apuntando a un JDK (con javac) de version suficiente, si hay alguno.
function Req-BuscarJdk {
    $candidatos = @()
    if ($env:JAVA_HOME) { $candidatos += (Join-Path $env:JAVA_HOME 'bin\javac.exe') }
    $enPath = Get-Command javac -ErrorAction SilentlyContinue
    if ($enPath) { $candidatos += $enPath.Source }
    foreach ($patron in @("$env:ProgramFiles\Eclipse Adoptium\jdk-*", "$env:ProgramFiles\Java\jdk-*",
                          "$env:ProgramFiles\Microsoft\jdk-*", "$env:ProgramFiles\Android\Android Studio\jbr")) {
        foreach ($dir in @(Get-Item $patron -ErrorAction SilentlyContinue)) {
            $candidatos += (Join-Path $dir.FullName 'bin\javac.exe')
        }
    }
    foreach ($javac in $candidatos) {
        if (-not (Test-Path $javac)) { continue }
        if ((Req-JavacMayor $javac) -ge $ReqJavaMinimo) {
            $casa = Split-Path -Parent (Split-Path -Parent $javac)
            $env:JAVA_HOME = $casa
            $bin = Join-Path $casa 'bin'
            if ($env:Path -notlike "*$bin*") { $env:Path = "$bin;$env:Path" }
            return $true
        }
    }
    return $false
}

function Req-FlutterBin {
    $c = Get-Command flutter -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $propio = Join-Path $ReqFlutterDir 'bin\flutter.bat'
    if (Test-Path $propio) { return $propio }
    return $null
}

function Req-FlutterVersion {
    $bin = Req-FlutterBin
    if (-not $bin) { return $null }
    $raiz = Split-Path -Parent (Split-Path -Parent $bin)
    $json = Join-Path $raiz 'bin\cache\flutter.version.json'
    if (Test-Path $json) {
        $m = [regex]::Match((Get-Content $json -Raw), '"frameworkVersion"\s*:\s*"([0-9.]+)"')
        if ($m.Success) { return $m.Groups[1].Value }
    }
    $linea = (& $bin --version 2>$null | Select-Object -First 1 | Out-String).Trim()
    if ($linea -match '^Flutter\s+([0-9.]+)') { return $Matches[1] }
    return $null
}

function Req-SdkDir {
    foreach ($c in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
}

function Req-Sdkmanager {
    $sdk = Req-SdkDir
    foreach ($c in @((Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'))) {
        if (Test-Path $c) { return $c }
    }
    foreach ($f in @(Get-ChildItem (Join-Path $sdk 'cmdline-tools') -Directory -ErrorAction SilentlyContinue)) {
        $c = Join-Path $f.FullName 'bin\sdkmanager.bat'
        if (Test-Path $c) { return $c }
    }
    $g = Get-Command sdkmanager -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    return $null
}

function Req-AvdDir {
    if ($env:ANDROID_AVD_HOME) { return $env:ANDROID_AVD_HOME }
    if ($env:ANDROID_USER_HOME) { return (Join-Path $env:ANDROID_USER_HOME 'avd') }
    return (Join-Path $env:USERPROFILE '.android\avd')
}
function Req-AvdExiste([string]$Nombre) { return (Test-Path (Join-Path (Req-AvdDir) "$Nombre.ini")) }
function Req-HayAvd { return [bool](@(Get-ChildItem (Req-AvdDir) -Filter *.ini -ErrorAction SilentlyContinue).Count) }

function Req-WslOk {
    if (-not (Req-Tiene 'wsl.exe')) { return $false }
    & wsl.exe --status *> $null
    return ($LASTEXITCODE -eq 0)
}

function Req-DockerInstalado {
    if (Req-Tiene 'docker') { return $true }
    return (Test-Path (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'))
}

function Req-DetectarSdk {
    $sdk = Req-SdkDir
    if (-not (Req-Sdkmanager)) { Req-Falta 'sdk-cmdline' }
    $falta = $false
    if (-not (Test-Path (Join-Path $sdk 'platform-tools\adb.exe'))) { $falta = $true }
    if (-not ((Test-Path (Join-Path $sdk 'platforms\android-37.0')) -or (Test-Path (Join-Path $sdk 'platforms\android-37')))) { $falta = $true }
    if (-not (Test-Path (Join-Path $sdk 'build-tools\36.0.0'))) { $falta = $true }
    if (-not (Test-Path (Join-Path $sdk 'licenses\android-sdk-license'))) { $falta = $true }
    if ($falta) { Req-Falta 'sdk-paquetes' }
    if (Req-QuiereEmulador) {
        $emu = Join-Path $sdk 'emulator\emulator.exe'
        if (-not (Test-Path $emu)) { Req-Falta 'emulador' }
        if (-not (Test-Path (Join-Path $sdk 'system-images\android-33\google_apis\x86_64'))) { Req-Falta 'imagen' }
        if (-not ((Req-AvdExiste $ReqAvdDefecto) -or (Req-HayAvd))) { Req-Falta 'avd' }
        if (Test-Path $emu) {
            & $emu -accel-check *> $null
            if ($LASTEXITCODE -ne 0) { Req-Falta 'hipervisor' }
        }
    }
}

# Llena ReqFalta y ReqAvisos segun el modo.
function Req-Detectar {
    $script:ReqFalta = @(); $script:ReqAvisos = @()
    if (-not (Req-Tiene 'git')) { Req-Falta 'git' }
    if (-not (Req-DockerInstalado)) {
        Req-Falta 'docker'
        if (-not (Req-WslOk)) { Req-Falta 'wsl' }
    }
    if (Req-QuiereFlutter) {
        if (-not (Req-BuscarJdk)) { Req-Falta 'jdk' }
        $v = Req-FlutterVersion
        if (-not $v) {
            Req-Falta 'flutter'
        } elseif (-not (Req-VersionGe $v $ReqFlutterVersion)) {
            $script:ReqAvisos += "Flutter $v es anterior a $ReqFlutterVersion (la version del CI). No se actualiza solo: 'flutter upgrade'."
        }
        Req-DetectarSdk
    }
}

# --- informar ---------------------------------------------------------------------------------------
function Req-ListaCompleta([string[]]$Ids) {
    foreach ($id in $Ids) {
        if (Req-EnFalta $id) { Write-Host ('  [falta]     ' + (Req-Nombre $id)) }
        else { Write-Host ('  [instalado] ' + (Req-Nombre $id)) }
    }
}

function Req-Informe {
    Paso 'Requisitos'
    Req-ListaCompleta @('git', 'docker')
    if (Req-EnFalta 'docker') { Req-ListaCompleta @('wsl') }
    if (Req-QuiereFlutter) {
        Req-ListaCompleta @('jdk', 'flutter', 'sdk-cmdline', 'sdk-paquetes')
        if (Req-QuiereEmulador) { Req-ListaCompleta @('emulador', 'imagen', 'avd', 'hipervisor') }
    }
    foreach ($a in $script:ReqAvisos) { Info "AVISO: $a" }
}

function Req-Plan {
    Info 'Faltan estos requisitos y se van a instalar:'
    $total = 0
    foreach ($id in $script:ReqFalta) {
        $mb = Req-Mb $id
        $total += $mb
        if ($mb -gt 0) { Info "  - $(Req-Nombre $id)  (~$mb MB)" } else { Info "  - $(Req-Nombre $id)" }
    }
    $gb = [math]::Round($total / 1024.0, 1)
    Info "Descarga total aproximada: ~$gb GB. Windows pedira permiso de administrador para Docker y WSL."
}

# --- instalar ---------------------------------------------------------------------------------------
# Windows no actualiza el PATH de este proceso al instalar algo: se relee del registro.
function Req-RefrescarPath {
    $maquina = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $usuario = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$maquina;$usuario"
}

function Req-Winget([string]$Id, [string]$Nombre) {
    if (-not (Req-Tiene 'winget')) {
        Mal "No encuentro 'winget' (viene con 'Instalador de aplicacion' de Microsoft Store)."
        Info "Instala $Nombre a mano y vuelve a correr el script, o instala 'App Installer' desde Microsoft Store."
        return $false
    }
    Info "Instalando $Nombre con winget (puede abrir un aviso de Windows pidiendo permiso)..."
    & winget install --id $Id -e --silent --accept-package-agreements --accept-source-agreements
    if (($LASTEXITCODE -ne 0) -and ($LASTEXITCODE -ne $ReqWingetYaInstalado)) {
        Mal "winget no pudo instalar $Nombre (codigo $LASTEXITCODE)."
        return $false
    }
    $script:ReqInstalado = $true
    Req-RefrescarPath
    return $true
}

# Corre un comando de PowerShell elevado (aviso de UAC) y espera. Devuelve el codigo de salida.
function Req-Elevado([string]$Comando) {
    $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $Comando)
    return $p.ExitCode
}

function Req-InstalarWsl {
    if (-not (Req-EnFalta 'wsl')) { return $true }
    Paso 'Instalando WSL 2'
    $codigo = Req-Elevado 'wsl.exe --install --no-distribution; exit $LASTEXITCODE'
    if ($codigo -ne 0) {
        Mal "No se pudo instalar WSL 2 (codigo $codigo). Corre 'wsl --install' en una PowerShell como administrador."
        return $false
    }
    $script:ReqReiniciar = $true
    $script:ReqInstalado = $true
    return $true
}

function Req-Descargar([string]$Url, [string]$Destino) {
    # curl.exe viene con Windows 10 (1803+) y muestra progreso; Invoke-WebRequest es muy lento con archivos grandes.
    if (Req-Tiene 'curl.exe') {
        & curl.exe -fL --retry 3 --retry-delay 2 -o $Destino $Url
        return ($LASTEXITCODE -eq 0)
    }
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -OutFile $Destino -UseBasicParsing
    return (Test-Path $Destino)
}

function Req-VerificarSha256([string]$Archivo, [string]$Esperado) {
    $real = (Get-FileHash -Path $Archivo -Algorithm SHA256).Hash.ToLower()
    if ($real -ne $Esperado.ToLower()) {
        Mal "El sha256 de $(Split-Path -Leaf $Archivo) no coincide (esperado $Esperado, real $real)."
        return $false
    }
    return $true
}

function Req-HayEspacio([int]$Mb, [string]$Dir) {
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    $unidad = (Get-Item $Dir).PSDrive
    $libreMb = [math]::Floor($unidad.Free / 1MB)
    if ($libreMb -lt $Mb) {
        Mal "No hay espacio suficiente en $Dir`: hacen falta ~$Mb MB y hay $libreMb MB libres."
        return $false
    }
    return $true
}

function Req-InstalarFlutter {
    if (-not (Req-EnFalta 'flutter')) { return $true }
    Paso "Instalando Flutter $ReqFlutterVersion"
    $padre = Split-Path -Parent $ReqFlutterDir
    if (-not (Req-HayEspacio 6000 $padre)) { return $false }
    if (Test-Path $ReqFlutterDir) {
        $viejo = "$ReqFlutterDir.incompleto-$(Get-Date -Format yyyyMMddHHmmss)"
        Move-Item $ReqFlutterDir $viejo
        Info "Habia una carpeta de Flutter incompleta; quedo como $(Split-Path -Leaf $viejo)."
    }
    $zip = Join-Path $padre 'flutter_descarga.zip'
    try {
        Info 'Descargando (~1,9 GB)...'
        if (-not (Req-Descargar $ReqFlutterUrl $zip)) { Mal 'No se pudo descargar Flutter.'; return $false }
        if (-not (Req-VerificarSha256 $zip $ReqFlutterSha256)) { return $false }
        Info 'Descomprimiendo...'
        & tar.exe -xf $zip -C $padre
        if ($LASTEXITCODE -ne 0) { Mal 'No se pudo descomprimir Flutter.'; return $false }
    } finally {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
    }
    $env:Path = "$(Join-Path $ReqFlutterDir 'bin');$env:Path"
    $script:ReqInstalado = $true
    Bien "Flutter $ReqFlutterVersion instalado en $ReqFlutterDir."
    return $true
}

function Req-InstalarCmdline {
    if (-not (Req-EnFalta 'sdk-cmdline')) { return $true }
    Paso 'Instalando las herramientas de linea de comandos de Android'
    $sdk = Req-SdkDir
    if (-not (Req-HayEspacio 3500 $sdk)) { return $false }
    $tmp = Join-Path $sdk '_descarga'
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $zip = Join-Path $tmp 'cmdline.zip'
        if (-not (Req-Descargar $ReqCmdlineUrl $zip)) { Mal 'No se pudo descargar las herramientas.'; return $false }
        if (-not (Req-VerificarSha256 $zip $ReqCmdlineSha256)) { return $false }
        & tar.exe -xf $zip -C $tmp
        if ($LASTEXITCODE -ne 0) { Mal 'No se pudo descomprimir las herramientas.'; return $false }
        New-Item -ItemType Directory -Force -Path (Join-Path $sdk 'cmdline-tools') | Out-Null
        $destino = Join-Path $sdk 'cmdline-tools\latest'
        if (Test-Path $destino) { Remove-Item $destino -Recurse -Force }
        Move-Item (Join-Path $tmp 'cmdline-tools') $destino
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    $script:ReqInstalado = $true
    Bien "Herramientas instaladas en $sdk\cmdline-tools\latest."
    return $true
}

function Req-InstalarSdk {
    if (-not ((Req-EnFalta 'sdk-paquetes') -or (Req-EnFalta 'emulador') -or (Req-EnFalta 'imagen'))) { return $true }
    Paso 'Instalando el SDK de Android'
    $sdk = Req-SdkDir
    $mgr = Req-Sdkmanager
    if (-not $mgr) { Mal 'No encuentro sdkmanager.'; return $false }
    if (-not (Req-BuscarJdk)) { Mal "No hay un JDK $ReqJavaMinimo+ para correr sdkmanager."; return $false }
    $paquetes = @('platform-tools', $ReqPlataforma, $ReqBuildTools)
    if (Req-QuiereEmulador) { $paquetes += @('emulator', $ReqImagen) }
    Info "Paquetes: $($paquetes -join ' ')"
    $si = 1..80 | ForEach-Object { 'y' }
    $si | & $mgr "--sdk_root=$sdk" --licenses *> $null
    $si | & $mgr "--sdk_root=$sdk" @paquetes
    if ($LASTEXITCODE -ne 0) { Mal 'sdkmanager no pudo instalar los paquetes.'; return $false }
    $env:ANDROID_HOME = $sdk
    $env:ANDROID_SDK_ROOT = $sdk
    foreach ($d in @('cmdline-tools\latest\bin', 'platform-tools', 'emulator')) {
        $ruta = Join-Path $sdk $d
        if ($env:Path -notlike "*$ruta*") { $env:Path = "$ruta;$env:Path" }
    }
    $script:ReqInstalado = $true
    return $true
}

function Req-CrearAvd([string]$Nombre) {
    if (Req-AvdExiste $Nombre) { return $true }
    $sdk = Req-SdkDir
    $avdm = Join-Path $sdk 'cmdline-tools\latest\bin\avdmanager.bat'
    if (-not (Test-Path $avdm)) { Mal 'No encuentro avdmanager para crear el emulador.'; return $false }
    Paso "Creando el emulador $Nombre"
    Req-BuscarJdk | Out-Null
    'no' | & $avdm create avd --force -n $Nombre -k $ReqImagen -d pixel_5 *> $null
    if ($LASTEXITCODE -ne 0) { Mal "avdmanager no pudo crear $Nombre."; return $false }
    $config = Join-Path (Req-AvdDir) "$Nombre.avd\config.ini"
    if (Test-Path $config) {
        $lineas = @(Get-Content $config | Where-Object { $_ -notmatch '^hw\.ramSize=' })
        Set-Content -Path $config -Value ($lineas + 'hw.ramSize=2048') -Encoding ascii
    }
    $script:ReqInstalado = $true
    Bien "Emulador $Nombre creado."
    return $true
}

# El emulador de Android necesita la Plataforma del hipervisor de Windows; habilitarla pide administrador y reinicio.
function Req-InstalarHipervisor {
    if (-not (Req-EnFalta 'hipervisor')) { return $true }
    Paso 'Activando la Plataforma del hipervisor de Windows'
    $codigo = Req-Elevado 'Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform,VirtualMachinePlatform -NoRestart | Out-Null; exit 0'
    if ($codigo -ne 0) {
        Mal 'No se pudo activar la Plataforma del hipervisor. Activala en "Activar o desactivar las caracteristicas de Windows".'
        return $false
    }
    $script:ReqReiniciar = $true
    $script:ReqInstalado = $true
    return $true
}

# Variables de entorno del usuario: asi 'flutter run' funciona en otras terminales.
function Req-PersistirEntorno {
    if (-not $script:ReqInstalado) { return }
    $sdk = Req-SdkDir
    [Environment]::SetEnvironmentVariable('ANDROID_HOME', $sdk, 'User')
    [Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $sdk, 'User')
    if ($env:JAVA_HOME) { [Environment]::SetEnvironmentVariable('JAVA_HOME', $env:JAVA_HOME, 'User') }
    $usuario = [Environment]::GetEnvironmentVariable('Path', 'User')
    $nuevos = @((Join-Path $ReqFlutterDir 'bin'), (Join-Path $sdk 'cmdline-tools\latest\bin'),
                (Join-Path $sdk 'platform-tools'), (Join-Path $sdk 'emulator'))
    foreach ($n in $nuevos) {
        if ((Test-Path $n) -and (($usuario -split ';') -notcontains $n)) { $usuario = "$n;$usuario" }
    }
    [Environment]::SetEnvironmentVariable('Path', $usuario, 'User')
    Info 'Deje ANDROID_HOME y el PATH en las variables de tu usuario (abre una terminal nueva para verlos).'
}

function Req-ConfigurarFlutter {
    if (-not (Req-FlutterBin)) { return }
    if (-not (Req-QuiereFlutter)) { return }
    $sdk = Req-SdkDir
    if (Test-Path $sdk) { & flutter config --android-sdk $sdk *> $null }
    if ($env:JAVA_HOME) { & flutter config --jdk-dir $env:JAVA_HOME *> $null }
}

# Lo ya instalado pero fuera del PATH (el SDK de Android, Flutter en C:\src\flutter) queda a la vista de este proceso.
function Req-ExportarEntorno {
    $sdk = Req-SdkDir
    if (Test-Path $sdk) {
        if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = $sdk }
        if (-not $env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT = $sdk }
        foreach ($d in @('cmdline-tools\latest\bin', 'platform-tools', 'emulator')) {
            $ruta = Join-Path $sdk $d
            if ((Test-Path $ruta) -and ($env:Path -notlike "*$ruta*")) { $env:Path = "$ruta;$env:Path" }
        }
    }
    $fb = Join-Path $ReqFlutterDir 'bin'
    if ((Test-Path $fb) -and ($env:Path -notlike "*$fb*")) { $env:Path = "$fb;$env:Path" }
}

# --- punto de entrada ----------------------------------------------------------------------------------------
# Usa las variables de levantar.ps1 ($Comprobar, $SinInstalar, $SoloInstalar, $SinEmulador, $Telefono).
function Asegurar-Requisitos {
    Req-ExportarEntorno
    Req-Detectar

    if ($Comprobar) {
        Req-Informe
        if ($script:ReqFalta.Count -gt 0) {
            Info "Faltan $($script:ReqFalta.Count) requisito(s). Corre sin -Comprobar para instalarlos."
            exit 1
        }
        Bien 'Todo presente.'
        exit 0
    }

    if ($script:ReqFalta.Count -eq 0) {
        Req-ConfigurarFlutter
        if ($SoloInstalar) { Bien 'Todo presente: no habia nada que instalar.'; exit 0 }
        return
    }

    if ($SinInstalar) {
        Req-Informe
        Mal 'Faltan requisitos y se pidio no instalarlos (-SinInstalar).'
        exit 1
    }

    Paso 'Requisitos que faltan'
    Req-Plan
    if (Req-EnFalta 'wsl') { if (-not (Req-InstalarWsl)) { exit 1 } }
    if (Req-EnFalta 'git') { if (-not (Req-Winget 'Git.Git' 'Git')) { exit 1 } }
    if (Req-EnFalta 'jdk') { if (-not (Req-Winget 'EclipseAdoptium.Temurin.21.JDK' 'JDK 21')) { exit 1 } }
    if (Req-EnFalta 'docker') { if (-not (Req-Winget 'Docker.DockerDesktop' 'Docker Desktop')) { exit 1 } }
    Req-BuscarJdk | Out-Null
    if (-not (Req-InstalarFlutter)) { exit 1 }
    if (-not (Req-InstalarCmdline)) { exit 1 }
    if (-not (Req-InstalarSdk)) { exit 1 }
    if (Req-EnFalta 'avd') { if (-not (Req-CrearAvd $ReqAvdDefecto)) { exit 1 } }
    if (-not (Req-InstalarHipervisor)) { exit 1 }
    Req-ConfigurarFlutter
    Req-PersistirEntorno
    foreach ($a in $script:ReqAvisos) { Info "AVISO: $a" }

    if ($script:ReqReiniciar) {
        Paso 'Hay que reiniciar Windows'
        Info 'WSL 2 y/o el hipervisor quedan activos recien despues de reiniciar.'
        Info 'Reinicia el equipo y vuelve a correr scripts\levantar.ps1: sigue desde donde quedo.'
        exit 3010
    }
    Bien 'Requisitos instalados.'
    if ($SoloInstalar) { exit 0 }
}
