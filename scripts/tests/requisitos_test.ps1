<#
Pruebas de la logica de scripts\lib\requisitos.ps1 que no dependen de Windows: comparacion de versiones,
lectura de la version de Java, y el flujo de Asegurar-Requisitos con la deteccion simulada.
Corre en Windows PowerShell 5.1 y tambien en PowerShell 7 (por ejemplo en Linux, dentro de un contenedor).
No instala nada ni toca el sistema.

  pwsh -NoProfile -File scripts/tests/requisitos_test.ps1
#>
$ErrorActionPreference = 'Stop'
$Lib = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\requisitos.ps1'
if (-not (Test-Path $Lib)) { $Lib = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/requisitos.ps1' }
$Shell = (Get-Process -Id $PID).Path

$script:ok = 0
$script:fallas = 0
function Pasa([string]$n) { $script:ok++; Write-Host "  ok    $n" }
function Falla([string]$n, [string]$d) { $script:fallas++; Write-Host "  FALLA $n"; if ($d) { Write-Host "        $d" } }
function Igual([string]$n, $real, $esperado) {
    if ("$real" -eq "$esperado") { Pasa $n } else { Falla $n "esperado [$esperado], obtenido [$real]" }
}
function Contiene([string]$n, [string]$texto, [string]$trozo) {
    if ($texto.Contains($trozo)) { Pasa $n } else { Falla $n "no contiene [$trozo] en: $texto" }
}

# Funciones de salida de levantar.ps1 (la libreria las usa), y los flags que lee del script que la carga.
$Preludio = @'
function Paso($t) { Write-Host $t }
function Info($t) { Write-Host "  $t" }
function Bien($t) { Write-Host "  $t" }
function Mal($t)  { Write-Host "  $t" }
'@

# Corre un fragmento en un proceso aparte con la libreria cargada; devuelve salida y codigo de salida.
function En-Proceso([string]$Fragmento) {
    $codigo = "$Preludio`n. '$Lib'`n$Fragmento"
    $salida = & $Shell -NoProfile -Command $codigo 2>&1 | Out-String
    return @{ Salida = $salida; Codigo = $LASTEXITCODE }
}

# --- utilidades --------------------------------------------------------------------------------
Write-Host 'utilidades'
. ([scriptblock]::Create($Preludio))
. $Lib
Igual '3.47.1 >= 3.47.1' (Req-VersionGe '3.47.1' '3.47.1') 'True'
Igual '3.50.1 >= 3.47.1' (Req-VersionGe '3.50.1' '3.47.1') 'True'
Igual '3.46.9 < 3.47.1' (Req-VersionGe '3.46.9' '3.47.1') 'False'
Igual '3.47.10 >= 3.47.2 (numeros, no texto)' (Req-VersionGe '3.47.10' '3.47.2') 'True'
Igual 'java "21.0.13.1" -> 21' (Req-JavaMayor 'openjdk version "21.0.13.1" 2026-11-17') 21
Igual 'java "17.0.9" -> 17' (Req-JavaMayor 'openjdk version "17.0.9" 2023-10-17') 17
Igual 'java "1.8.0_392" -> 8' (Req-JavaMayor 'openjdk version "1.8.0_392"') 8
Igual 'javac 21.0.1 -> 21' (Req-JavaMayor 'javac 21.0.1') 21
Igual 'linea vacia -> 0' (Req-JavaMayor '') 0
Igual 'las versiones fijadas coinciden con ci.yml' $ReqFlutterVersion ((Select-String -Path (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Lib))) '.github\workflows\ci.yml') -Pattern "flutter-version: '([0-9.]+)'").Matches[0].Groups[1].Value)

# --- flujo de Asegurar-Requisitos con la deteccion simulada ----------------------------------------
Write-Host 'flujo'
$Sim = @'
function Req-ExportarEntorno { }
function Req-Detectar { $script:ReqFalta = @('docker', 'flutter'); $script:ReqAvisos = @() }
$SinEmulador = $false; $Telefono = $false
'@
$SimTodo = @'
function Req-ExportarEntorno { }
function Req-Detectar { $script:ReqFalta = @(); $script:ReqAvisos = @() }
function Req-ConfigurarFlutter { }
$SinEmulador = $false; $Telefono = $false
'@

$r = En-Proceso "$Sim`n`$Comprobar = `$true; Asegurar-Requisitos"
Igual '-Comprobar con faltantes: sale con 1' $r.Codigo 1
Contiene '-Comprobar lista Docker Desktop como faltante' $r.Salida '[falta]     Docker Desktop'

$r = En-Proceso "$Sim`n`$SinInstalar = `$true; Asegurar-Requisitos"
Igual '-SinInstalar con faltantes: sale con 1' $r.Codigo 1
Contiene '-SinInstalar avisa' $r.Salida '-SinInstalar'

$r = En-Proceso "$SimTodo`n`$Comprobar = `$true; Asegurar-Requisitos"
Igual '-Comprobar con todo: sale con 0' $r.Codigo 0
Contiene '-Comprobar con todo: lo dice' $r.Salida 'Todo presente'

$r = En-Proceso "$SimTodo`n`$SoloInstalar = `$true; Asegurar-Requisitos"
Igual '-SoloInstalar con todo: sale con 0' $r.Codigo 0
Contiene '-SoloInstalar con todo: no habia nada' $r.Salida 'no habia nada que instalar'

$r = En-Proceso "$SimTodo`nAsegurar-Requisitos; Write-Host CONTINUA"
Igual 'sin flags y con todo: el script sigue' $r.Codigo 0
Contiene 'sin flags y con todo: continua' $r.Salida 'CONTINUA'

# Con faltantes y sin -SinInstalar se intentaria instalar: aca se reemplaza lo que instala para comprobar el orden.
$Orden = @'
function Req-ExportarEntorno { }
function Req-Detectar { $script:ReqFalta = @('wsl', 'git', 'jdk', 'docker', 'flutter', 'sdk-cmdline', 'sdk-paquetes', 'emulador', 'imagen', 'avd', 'hipervisor'); $script:ReqAvisos = @() }
$script:Llamadas = @()
function Req-InstalarWsl { $script:Llamadas += 'wsl'; $script:ReqReiniciar = $true; return $true }
function Req-Winget($id, $n) { $script:Llamadas += $n; return $true }
function Req-BuscarJdk { return $true }
function Req-InstalarFlutter { $script:Llamadas += 'flutter'; return $true }
function Req-InstalarCmdline { $script:Llamadas += 'cmdline'; return $true }
function Req-InstalarSdk { $script:Llamadas += 'sdk'; return $true }
function Req-CrearAvd($n) { $script:Llamadas += 'avd'; return $true }
function Req-InstalarHipervisor { $script:Llamadas += 'hipervisor'; return $true }
function Req-ConfigurarFlutter { }
function Req-PersistirEntorno { }
$SinEmulador = $false; $Telefono = $false
Asegurar-Requisitos
'@
$r = En-Proceso $Orden
# En Windows el codigo es 3010; en Linux (donde se prueba tambien) los codigos de salida son de 8 bits.
Igual 'con faltantes se detiene pidiendo reiniciar (3010)' ($r.Codigo % 256) (3010 % 256)
Contiene 'avisa que hay que reiniciar' $r.Salida 'Hay que reiniciar Windows'
# Mismo flujo pero sin que WSL pida reinicio, para poder imprimir el orden en que se instalo todo.
$SinReinicio = $Orden.Replace('$script:ReqReiniciar = $true; ', '').Replace('Asegurar-Requisitos', "Asegurar-Requisitos`nWrite-Host (`$script:Llamadas -join ',')")
$r2 = En-Proceso $SinReinicio
Contiene 'el orden: WSL, Git, JDK, Docker, Flutter, cmdline, SDK, AVD, hipervisor' $r2.Salida 'wsl,Git,JDK 21,Docker Desktop,flutter,cmdline,sdk,avd,hipervisor'

# --- conflictos de flags (los valida levantar.ps1, que solo se puede leer aca) ----------------------------
Write-Host 'levantar.ps1'
$ps1 = Get-Content (Join-Path (Split-Path -Parent (Split-Path -Parent $Lib)) 'levantar.ps1') -Raw
Contiene 'levantar.ps1 declara -Comprobar' $ps1 '[switch]$Comprobar'
Contiene 'levantar.ps1 declara -SinInstalar' $ps1 '[switch]$SinInstalar'
Contiene 'levantar.ps1 declara -SoloInstalar' $ps1 '[switch]$SoloInstalar'
Contiene 'levantar.ps1 carga el modulo' $ps1 "requisitos.ps1"

Write-Host ''
Write-Host ("Resultado: {0} ok, {1} fallas" -f $script:ok, $script:fallas)
if ($script:fallas -gt 0) { exit 1 }
