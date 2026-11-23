#!/usr/bin/env bash
# Pruebas de scripts/lib/requisitos.sh y de los flags nuevos de scripts/levantar.sh.
# No usan red ni instalan nada: arman un "computador" falso con un PATH que solo tiene binarios de
# mentira (y las utilidades basicas), un HOME temporal y un apt-get/sudo que solo anotan que los llamaron.
#
#   scripts/tests/requisitos_test.sh
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$RAIZ/scripts/lib/requisitos.sh"
LEVANTAR="$RAIZ/scripts/levantar.sh"
BASH_BIN="$(command -v bash)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok=0; fallas=0
pasa()  { ok=$((ok + 1)); printf '  ok    %s\n' "$1"; }
falla() { fallas=$((fallas + 1)); printf '  FALLA %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; }
igual() { if [[ "$2" == "$3" ]]; then pasa "$1"; else falla "$1" "esperado [$3], obtenido [$2]"; fi; }
contiene() { if [[ "$2" == *"$3"* ]]; then pasa "$1"; else falla "$1" "no contiene [$3] en: $2"; fi; }
no_contiene() { if [[ "$2" != *"$3"* ]]; then pasa "$1"; else falla "$1" "contiene [$3] en: $2"; fi; }

# --- el computador falso -------------------------------------------------------------------------
# Utilidades basicas de verdad (enlaces), para que el modulo corra; nada de docker, java, flutter...
BASICAS=(sed awk grep head tail sort tr dirname basename readlink uname id getent date df mktemp mv rm cat
         sha256sum tee env timeout mkdir ls cut printf wc sleep tar yes true false dpkg-query bash)

nuevo_equipo() {
  # nuevo_equipo NOMBRE -> prepara $TMP/NOMBRE/{bin,home}; imprime la ruta
  local e="$TMP/$1"
  rm -rf "$e"; mkdir -p "$e/bin" "$e/home" "$e/llamadas"
  local b ruta
  for b in "${BASICAS[@]}"; do
    ruta="$(command -v "$b" 2>/dev/null)" && [[ -x "$ruta" ]] && ln -s "$ruta" "$e/bin/$b"
  done
  # apt-get y sudo de mentira: solo dejan constancia
  printf '#!/bin/sh\necho "apt-get $*" >> "%s/llamadas/instalador"\n' "$e" > "$e/bin/apt-get"
  printf '#!/bin/sh\necho "sudo $*" >> "%s/llamadas/instalador"\nexit 0\n' "$e" > "$e/bin/sudo"
  chmod +x "$e/bin/apt-get" "$e/bin/sudo"
  printf '%s' "$e"
}

falso() {  # falso EQUIPO NOMBRE 'script sh'
  printf '#!/bin/sh\n%s\n' "$3" > "$1/bin/$2"; chmod +x "$1/bin/$2"
}

con_basicos() {  # git curl unzip xz python3 que existen
  local n
  for n in git curl unzip xz python3; do falso "$1" "$n" 'exit 0'; done
}

# shellcheck disable=SC2016  # el script falso debe llevar $1 literal
con_docker() { falso "$1" docker 'if [ "$1" = "compose" ]; then echo "Docker Compose version v5"; fi; exit 0'; }
con_java()   {
  falso "$1" java "echo 'openjdk version \"${2:-21.0.1}\" 2026-01-01' >&2"
  falso "$1" javac "echo 'javac ${2:-21.0.1}'"
}
con_flutter() { falso "$1" flutter "echo 'Flutter ${2:-3.47.1} - channel stable'"; }
con_sdk() {
  local sdk="$1/home/Android/Sdk"
  mkdir -p "$sdk/cmdline-tools/latest/bin" "$sdk/platform-tools" "$sdk/emulator" "$sdk/platforms/android-37.0" \
           "$sdk/build-tools/36.0.0" "$sdk/licenses" "$sdk/system-images/android-33/google_apis/x86_64" "$1/home/.android/avd"
  printf '#!/bin/sh\nexit 0\n' > "$sdk/cmdline-tools/latest/bin/sdkmanager"; chmod +x "$sdk/cmdline-tools/latest/bin/sdkmanager"
  printf '#!/bin/sh\nexit 0\n' > "$sdk/platform-tools/adb"; chmod +x "$sdk/platform-tools/adb"
  printf '#!/bin/sh\nexit 0\n' > "$sdk/emulator/emulator"; chmod +x "$sdk/emulator/emulator"
  echo aceptada > "$sdk/licenses/android-sdk-license"
  : > "$1/home/.android/avd/Check-In-Obra_Pixel5.ini"
}
equipo_completo() { con_basicos "$1"; con_docker "$1"; con_java "$1"; con_flutter "$1"; con_sdk "$1"; }

# Corre un fragmento con el modulo cargado dentro del equipo falso. Imprime lo que el fragmento imprima.
en_equipo() {
  local e="$1"; shift
  ( export HOME="$e/home" PATH="$e/bin" SHELL=/bin/bash REQ_JVM_DIR="$e/jvm"; unset ANDROID_HOME ANDROID_SDK_ROOT JAVA_HOME
    # shellcheck disable=SC1090
    source "$LIB"; "$@" ) 2>&1
}

# levantar.sh dentro del equipo falso: imprime la salida y deja el codigo en $CODIGO
levantar_en() {
  local e="$1"; shift
  SALIDA="$(HOME="$e/home" PATH="$e/bin" SHELL=/bin/bash REQ_JVM_DIR="$e/jvm" "$BASH_BIN" "$LEVANTAR" "$@" 2>&1)"; CODIGO=$?
}

# --- 1. utilidades -------------------------------------------------------------------------------
echo "utilidades"
E="$(nuevo_equipo util)"
vge() { en_equipo "$E" bash -c "source '$LIB'; req_version_ge $1 $2 && echo si || echo no"; }
igual "3.47.1 >= 3.47.1"  "$(vge 3.47.1 3.47.1)" si
igual "3.50.1 >= 3.47.1"  "$(vge 3.50.1 3.47.1)" si
igual "3.46.9 < 3.47.1"   "$(vge 3.46.9 3.47.1)" no
igual "3.47.10 >= 3.47.2 (compara numeros, no texto)" "$(vge 3.47.10 3.47.2)" si
igual "4.0.0 >= 3.47.1"   "$(vge 4.0.0 3.47.1)" si

jv() {  # jv 'texto que imprime java' -> version mayor
  falso "$E" java "echo '$1' >&2"; falso "$E" javac "echo '$1'"
  en_equipo "$E" req_java_mayor java
}
igual "java 21.0.13.1 -> 21" "$(jv 'openjdk version "21.0.13.1" 2026-11-17')" 21
igual "java 17.0.9 -> 17"    "$(jv 'openjdk version "17.0.9" 2023-10-17')" 17
igual "java 1.8.0_392 -> 8"  "$(jv 'openjdk version "1.8.0_392"')" 8
falso "$E" javac "echo 'javac 21.0.1'"
igual "javac 21.0.1 -> 21"   "$(en_equipo "$E" req_java_mayor javac)" 21

# --- 2. deteccion ----------------------------------------------------------------------------------
echo "deteccion"
faltas() { en_equipo "$1" bash -c "source '$LIB'; sin_emulador=${2:-0}; telefono=${3:-0}; req_detectar; echo \"\${REQ_FALTA[*]:-}\""; }

E="$(nuevo_equipo vacio)"
r="$(faltas "$E" 1)"
contiene "equipo vacio, --sin-emulador: falta docker" "$r" "docker"
contiene "equipo vacio: faltan git y python3" "$r" "apt:git"
no_contiene "--sin-emulador no pide Flutter" "$r" "flutter"
no_contiene "--sin-emulador no pide el SDK" "$r" "sdk-"

r="$(faltas "$E" 0)"
for x in jdk flutter sdk-cmdline sdk-paquetes emulador imagen avd; do contiene "equipo vacio, modo normal: falta $x" "$r" "$x"; done

E="$(nuevo_equipo tel)"; con_basicos "$E"; con_docker "$E"
r="$(faltas "$E" 1 1)"
contiene "--telefono pide Flutter" "$r" "flutter"
contiene "--telefono pide el SDK" "$r" "sdk-cmdline"
no_contiene "--telefono no pide emulador" "$r" "emulador"
no_contiene "--telefono no pide imagen" "$r" "imagen"
no_contiene "--telefono no pide AVD" "$r" "avd"

E="$(nuevo_equipo completo)"; equipo_completo "$E"
igual "equipo completo: no falta nada" "$(faltas "$E" 0)" ""

E="$(nuevo_equipo sincompose)"; equipo_completo "$E"; falso "$E" docker 'exit 1'
contiene "docker sin compose: falta compose" "$(faltas "$E" 1)" "compose"

E="$(nuevo_equipo javaviejo)"; equipo_completo "$E"; con_java "$E" 11.0.2
contiene "JDK 11 no sirve: falta jdk" "$(faltas "$E" 0)" "jdk"

E="$(nuevo_equipo flutterviejo)"; equipo_completo "$E"; con_flutter "$E" 3.40.0
r="$(en_equipo "$E" bash -c "source '$LIB'; sin_emulador=0; telefono=0; req_detectar; echo \"F=\${REQ_FALTA[*]:-} A=\${REQ_AVISOS[*]:-}\"")"
no_contiene "Flutter anterior: no se reinstala" "$r" "F=flutter"
contiene "Flutter anterior: avisa" "$r" "es anterior a"

E="$(nuevo_equipo jvmdir)"; equipo_completo "$E"; rm "$E/bin/java" "$E/bin/javac"
mkdir -p "$E/jvm/jdk-21/bin"; printf '#!/bin/sh\necho "javac 21.0.1"\n' > "$E/jvm/jdk-21/bin/javac"; chmod +x "$E/jvm/jdk-21/bin/javac"
printf '#!/bin/sh\necho "openjdk version \\"21.0.1\\"" >&2\n' > "$E/jvm/jdk-21/bin/java"; chmod +x "$E/jvm/jdk-21/bin/java"
no_contiene "un JDK solo en /usr/lib/jvm cuenta como instalado" "$(faltas "$E" 0)" "jdk"
contiene "y queda en JAVA_HOME" "$(en_equipo "$E" bash -c "source '$LIB'; req_buscar_jdk; echo \$JAVA_HOME")" "jdk-21"

E="$(nuevo_equipo avdotro)"; equipo_completo "$E"; rm "$E/home/.android/avd/Check-In-Obra_Pixel5.ini"; : > "$E/home/.android/avd/Otro.ini"
no_contiene "con otro AVD no se crea uno nuevo" "$(faltas "$E" 0)" "avd"

# --- 3. levantar.sh: flags -------------------------------------------------------------------------
echo "levantar.sh"
E="$(nuevo_equipo flags)"; con_basicos "$E"          # sin docker
levantar_en "$E" --comprobar --sin-emulador
igual "--comprobar con faltantes: sale con 1" "$CODIGO" 1
contiene "--comprobar lista Docker como faltante" "$SALIDA" "[falta]     Docker Engine"
igual "--comprobar no instala nada" "$(cat "$E/llamadas/instalador" 2>/dev/null)" ""

levantar_en "$E" --sin-instalar --sin-emulador
igual "--sin-instalar con faltantes: sale con 1" "$CODIGO" 1
contiene "--sin-instalar avisa" "$SALIDA" "--sin-instalar"
igual "--sin-instalar no instala nada" "$(cat "$E/llamadas/instalador" 2>/dev/null)" ""

E="$(nuevo_equipo todo)"; equipo_completo "$E"
levantar_en "$E" --comprobar
igual "--comprobar con todo: sale con 0" "$CODIGO" 0
contiene "--comprobar con todo: lo dice" "$SALIDA" "Todo presente"

levantar_en "$E" --solo-instalar
igual "--solo-instalar con todo: sale con 0" "$CODIGO" 0
contiene "--solo-instalar con todo: no habia nada" "$SALIDA" "no habia nada que instalar"
igual "con todo presente no se llama a apt ni a sudo" "$(cat "$E/llamadas/instalador" 2>/dev/null)" ""

levantar_en "$E" --comprobar --solo-instalar
igual "--comprobar y --solo-instalar se rechazan" "$CODIGO" 1
levantar_en "$E" --solo-instalar --sin-instalar
igual "--solo-instalar y --sin-instalar se rechazan" "$CODIGO" 1

# --- 4. piezas sueltas ----------------------------------------------------------------------------------
echo "piezas sueltas"
E="$(nuevo_equipo rc)"
persistir() { en_equipo "$E" bash -c "source '$LIB'; REQ_INSTALADO=1; REQ_FLUTTER_DIR='$E/home/development/flutter'; req_persistir_entorno >/dev/null; req_persistir_entorno >/dev/null"; }
persistir >/dev/null
igual "el rc queda con un solo bloque tras dos corridas" "$(grep -c '>>> Check-In-Obra >>>' "$E/home/.bashrc")" 1
contiene "el bloque define ANDROID_HOME" "$(cat "$E/home/.bashrc")" "ANDROID_HOME"

E="$(nuevo_equipo rc2)"
en_equipo "$E" bash -c "source '$LIB'; REQ_INSTALADO=0; req_persistir_entorno" >/dev/null
igual "sin haber instalado nada no se toca el rc" "$([[ -e "$E/home/.bashrc" ]] && echo existe || echo no)" no

igual "relanzar con grupo: una sola vez" "$(en_equipo "$E" bash -c "source '$LIB'; REQ_RELANZADO=1 req_relanzar_con_grupo docker true && echo si || echo no")" no

f="$TMP/dato"; echo hola > "$f"; h="$(sha256sum "$f" | awk '{print $1}')"
igual "sha256 correcto" "$(en_equipo "$E" bash -c "source '$LIB'; req_verificar_sha256 '$f' '$h' && echo si || echo no")" si
contiene "sha256 incorrecto se rechaza" "$(en_equipo "$E" bash -c "source '$LIB'; req_verificar_sha256 '$f' 000 && echo si || echo no")" "no coincide"
contiene "sin espacio se rechaza antes de descargar" "$(en_equipo "$E" bash -c "source '$LIB'; req_hay_espacio 999999999 '$TMP' && echo si || echo no")" "No hay espacio"

echo
printf 'Resultado: %d ok, %d fallas\n' "$ok" "$fallas"
(( fallas == 0 ))
