#!/usr/bin/env bash
# Requisitos de Check-In-Obra: detecta lo que falta en este computador y lo instala solo.
# Lo carga scripts/levantar.sh con 'source'; no se ejecuta suelto.
#
# Instala automaticamente en Ubuntu y Debian (apt). En otros sistemas solo dice que falta y como
# instalarlo a mano (en Windows lo hace scripts/levantar.ps1).
#
# Que se pide depende del modo, segun las variables que define levantar.sh:
#   sin_emulador=1   solo Docker (y lo basico)
#   telefono=1       + Flutter, JDK y el SDK de Android (sin emulador)
#   (por defecto)    + emulador, imagen del sistema y el AVD Check-In-Obra_Pixel5
#
# Es idempotente: con todo instalado no descarga ni instala nada. Las descargas se verifican con
# sha256; no se ejecuta nada bajado de internet con 'sh'. 'sudo' solo se usa para apt, los grupos
# y el servicio de Docker; Flutter y el SDK de Android van al directorio del usuario.

# --- versiones fijadas ---------------------------------------------------------------------------
# Mantener igual que .github/workflows/ci.yml (flutter-version) y mobile/android/app/build.gradle.kts
# (compileSdk). Los sha256 salen de releases_linux.json de Flutter y de la pagina de descargas de
# developer.android.com/studio.
REQ_FLUTTER_VERSION="3.47.1"
REQ_FLUTTER_SHA256_LINUX="a1d8166c0309267cb7dc99f1424eecf08b86946ad3b50723c6f59945964aea45"
REQ_FLUTTER_URL_LINUX="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${REQ_FLUTTER_VERSION}-stable.tar.xz"
REQ_CMDLINE_BUILD="15859902"
REQ_CMDLINE_SHA256_LINUX="4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583"
REQ_CMDLINE_URL_LINUX="https://dl.google.com/android/repository/commandlinetools-linux-${REQ_CMDLINE_BUILD}_latest.zip"
REQ_PLATAFORMA="platforms;android-37.0"
REQ_BUILD_TOOLS="build-tools;36.0.0"
REQ_AVD_DEFECTO="Check-In-Obra_Pixel5"
REQ_JAVA_MINIMO=17
REQ_FLUTTER_DIR="${REQ_FLUTTER_DIR:-$HOME/development/flutter}"

REQ_FALTA=()          # ids de lo que falta
REQ_AVISOS=()         # cosas que no se pueden instalar pero conviene saber
REQ_INSTALADO=0       # 1 si este script instalo algo (decide si se persiste el entorno)
REQ_SUDO=""

# Si levantar.sh no definio las funciones de salida (por ejemplo en las pruebas), se usan estas.
if ! declare -F paso >/dev/null; then
  paso() { printf '\n%s\n' "$1"; }
  info() { printf '  %s\n' "$1"; }
  bien() { printf '  %s\n' "$1"; }
  mal()  { printf '  %s\n' "$1" >&2; }
fi

# --- utilidades -----------------------------------------------------------------------------------
req_tiene() { command -v "$1" >/dev/null 2>&1; }

# req_version_ge A B -> 0 si la version A es mayor o igual que B (3.47.1 >= 3.47.1, 3.50.1 >= 3.47.1).
req_version_ge() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | LC_ALL=C sort -V | head -n1)" == "$2" ]]
}

req_es_debian() {
  [[ "$(uname -s)" == "Linux" ]] || return 1
  [[ -r /etc/os-release ]] || return 1
  # shellcheck disable=SC1091
  ( . /etc/os-release; [[ "${ID:-}" =~ ^(ubuntu|debian)$ || "${ID_LIKE:-}" =~ (ubuntu|debian) ]] ) \
    && req_tiene apt-get
}

req_arch_android() {
  case "$(uname -m)" in
    aarch64|arm64) printf 'arm64-v8a' ;;
    *)             printf 'x86_64' ;;
  esac
}

req_imagen_sdk() { printf 'system-images;android-33;google_apis;%s' "$(req_arch_android)"; }

# Necesidades segun el modo.
req_quiere_flutter()   { (( ! ${sin_emulador:-0} )) || (( ${telefono:-0} )); }
req_quiere_sdk()       { req_quiere_flutter; }
req_quiere_emulador()  { (( ! ${sin_emulador:-0} )); }

req_nombre() {
  case "$1" in
    apt:*)        printf 'Paquete del sistema: %s' "${1#apt:}" ;;
    docker)       printf 'Docker Engine' ;;
    compose)      printf 'Docker Compose (plugin)' ;;
    jdk)          printf 'JDK %s o superior' "$REQ_JAVA_MINIMO" ;;
    flutter)      printf 'Flutter %s o superior' "$REQ_FLUTTER_VERSION" ;;
    sdk-cmdline)  printf 'Herramientas de linea de comandos de Android' ;;
    sdk-paquetes) printf 'SDK de Android (plataforma, build-tools, platform-tools, licencias)' ;;
    emulador)     printf 'Emulador de Android' ;;
    imagen)       printf 'Imagen del sistema del emulador (Android 13)' ;;
    avd)          printf 'Emulador %s' "$REQ_AVD_DEFECTO" ;;
    kvm)          printf 'Permiso para usar KVM (acelera el emulador)' ;;
    *)            printf '%s' "$1" ;;
  esac
}

# Tamano aproximado de la descarga, en MB.
req_mb() {
  case "$1" in
    apt:*)        printf 30 ;;
    docker)       printf 450 ;;
    compose)      printf 30 ;;
    jdk)          printf 250 ;;
    flutter)      printf 1600 ;;
    sdk-cmdline)  printf 180 ;;
    sdk-paquetes) printf 250 ;;
    emulador)     printf 350 ;;
    imagen)       printf 1300 ;;
    *)            printf 0 ;;
  esac
}

req_falta() { REQ_FALTA+=("$1"); }

req_en_falta() {
  local x
  for x in "${REQ_FALTA[@]+"${REQ_FALTA[@]}"}"; do [[ "$x" == "$1" ]] && return 0; done
  return 1
}

# --- detectar ---------------------------------------------------------------------------------------
req_detectar_base() {
  local par cmd pkg
  for par in git:git curl:curl unzip:unzip xz:xz-utils python3:python3; do
    cmd="${par%%:*}"; pkg="${par#*:}"
    req_tiene "$cmd" || req_falta "apt:$pkg"
  done
}

req_detectar_docker() {
  if ! req_tiene docker; then
    req_falta docker
  elif ! docker compose version >/dev/null 2>&1; then
    req_falta compose
  fi
}

# Version mayor de 'java -version' / 'javac -version' ("21.0.13.1", "17.0.9", "1.8.0_392", "javac 21.0.1").
req_java_mayor() {
  local linea v
  linea="$(LC_ALL=C "$1" -version 2>&1 | head -n1)"
  if [[ "$linea" == *\"* ]]; then
    v="$(sed -E 's/^[^"]*"([^"]+)".*/\1/' <<<"$linea")"
  else
    v="$(awk '{print $2}' <<<"$linea")"
  fi
  [[ "$v" == 1.* ]] && v="${v#1.}"
  printf '%s' "${v%%[!0-9]*}"
}

# Deja en JAVA_HOME un JDK (con javac) de version suficiente, si hay alguno. 0 si lo hay.
req_buscar_jdk() {
  local casa cand mayor
  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/javac" ]]; then
    mayor="$(req_java_mayor "$JAVA_HOME/bin/javac")"
    [[ "$mayor" =~ ^[0-9]+$ ]] && (( mayor >= REQ_JAVA_MINIMO )) && return 0
  fi
  if req_tiene javac && req_tiene java; then
    mayor="$(req_java_mayor javac)"
    [[ "$mayor" =~ ^[0-9]+$ ]] && (( mayor >= REQ_JAVA_MINIMO )) && return 0
  fi
  for cand in "${REQ_JVM_DIR:-/usr/lib/jvm}"/*/bin/javac; do
    [[ -x "$cand" ]] || continue
    mayor="$(req_java_mayor "$cand")"
    if [[ "$mayor" =~ ^[0-9]+$ ]] && (( mayor >= REQ_JAVA_MINIMO )); then
      casa="$(dirname "$(dirname "$cand")")"
      export JAVA_HOME="$casa"
      export PATH="$casa/bin:$PATH"
      return 0
    fi
  done
  return 1
}

# Ruta del ejecutable de flutter (en el PATH o en el directorio que usa este script).
req_flutter_bin() {
  if req_tiene flutter; then command -v flutter; return 0; fi
  [[ -x "$REQ_FLUTTER_DIR/bin/flutter" ]] && { printf '%s' "$REQ_FLUTTER_DIR/bin/flutter"; return 0; }
  return 1
}

req_flutter_version() {
  local bin raiz v
  bin="$(req_flutter_bin)" || return 1
  raiz="$(dirname "$(dirname "$(readlink -f "$bin" 2>/dev/null || echo "$bin")")")"
  if [[ -r "$raiz/bin/cache/flutter.version.json" ]]; then
    v="$(sed -nE 's/.*"frameworkVersion"[[:space:]]*:[[:space:]]*"([0-9.]+)".*/\1/p' "$raiz/bin/cache/flutter.version.json" | head -n1)"
  elif [[ -r "$raiz/version" ]]; then
    v="$(head -n1 "$raiz/version" | tr -d '\r')"
  fi
  if [[ -z "${v:-}" ]]; then
    v="$(LC_ALL=C timeout 180 "$bin" --version 2>/dev/null | sed -nE 's/^Flutter ([0-9.]+).*/\1/p' | head -n1)"
  fi
  [[ -n "$v" ]] && printf '%s' "$v"
}

req_detectar_flutter() {
  local v
  if ! v="$(req_flutter_version)"; then
    req_falta flutter
  elif ! req_version_ge "$v" "$REQ_FLUTTER_VERSION"; then
    REQ_AVISOS+=("Flutter $v es anterior a $REQ_FLUTTER_VERSION (la version del CI). No se actualiza solo: 'flutter upgrade' o borrar y volver a correr.")
  fi
}

# Directorio del SDK de Android: el primero que ya existe, o el de siempre.
req_sdk_dir() {
  local c
  for c in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk"; do
    [[ -n "$c" && -d "$c" ]] && { printf '%s' "$c"; return 0; }
  done
  printf '%s' "$HOME/Android/Sdk"
}

req_sdkmanager() {
  local sdk c
  sdk="$(req_sdk_dir)"
  for c in "$sdk/cmdline-tools/latest/bin/sdkmanager" "$sdk"/cmdline-tools/*/bin/sdkmanager; do
    [[ -x "$c" ]] && { printf '%s' "$c"; return 0; }
  done
  req_tiene sdkmanager && { command -v sdkmanager; return 0; }
  return 1
}

req_avd_dir() {
  local dir="${ANDROID_AVD_HOME:-${ANDROID_USER_HOME:+$ANDROID_USER_HOME/avd}}"
  printf '%s' "${dir:-$HOME/.android/avd}"
}

req_avd_existe() { [[ -f "$(req_avd_dir)/$1.ini" ]]; }

# Hay algun emulador creado? levantar.sh usa Check-In-Obra_Pixel5 o, si no esta, el primero que haya.
req_hay_avd() {
  local f
  for f in "$(req_avd_dir)"/*.ini; do [[ -f "$f" ]] && return 0; done
  return 1
}

req_detectar_sdk() {
  local sdk falta=0
  sdk="$(req_sdk_dir)"
  req_sdkmanager >/dev/null || req_falta sdk-cmdline
  [[ -x "$sdk/platform-tools/adb" ]] || falta=1
  [[ -d "$sdk/platforms/android-37.0" || -d "$sdk/platforms/android-37" ]] || falta=1
  [[ -d "$sdk/build-tools/36.0.0" ]] || falta=1
  [[ -f "$sdk/licenses/android-sdk-license" ]] || falta=1
  (( falta )) && req_falta sdk-paquetes
  if req_quiere_emulador; then
    [[ -x "$sdk/emulator/emulator" ]] || req_falta emulador
    [[ -d "$sdk/system-images/android-33/google_apis/$(req_arch_android)" ]] || req_falta imagen
    req_avd_existe "$REQ_AVD_DEFECTO" || req_hay_avd || req_falta avd
  fi
  return 0
}

req_detectar_kvm() {
  req_quiere_emulador || return 0
  [[ "$(uname -s)" == "Linux" ]] || return 0
  if [[ ! -e /dev/kvm ]]; then
    REQ_AVISOS+=("Este equipo no expone /dev/kvm: el emulador x86 no funciona sin virtualizacion. Activa VT-x/AMD-V en la BIOS, o usa --telefono / --sin-emulador.")
  elif [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
    req_falta kvm
  fi
}

# Llena REQ_FALTA y REQ_AVISOS segun el modo.
req_detectar() {
  REQ_FALTA=(); REQ_AVISOS=()
  req_detectar_base
  req_detectar_docker
  if req_quiere_flutter; then
    req_buscar_jdk || req_falta jdk
    req_detectar_flutter
    req_detectar_sdk
    req_detectar_kvm
  fi
}

# --- informar ---------------------------------------------------------------------------------------
req_lista_completa() {
  # presente o ausente de cada id, para --comprobar
  local id
  for id in "$@"; do
    if req_en_falta "$id"; then
      printf '  [falta]     %s\n' "$(req_nombre "$id")"
    else
      printf '  [instalado] %s\n' "$(req_nombre "$id")"
    fi
  done
}

req_informe() {
  local par ids
  paso "Requisitos"
  for par in apt:git apt:curl apt:unzip apt:xz-utils apt:python3; do
    req_lista_completa "$par"
  done
  ids=(docker)
  req_en_falta docker || ids+=(compose)
  req_lista_completa "${ids[@]}"
  if req_quiere_flutter; then
    req_lista_completa jdk flutter sdk-cmdline sdk-paquetes
    if req_quiere_emulador; then
      req_lista_completa emulador imagen avd
      # La fila de KVM solo tiene sentido si el equipo lo expone; si no, ya sale el aviso.
      [[ -e /dev/kvm ]] && req_lista_completa kvm
    fi
  fi
  local a
  for a in "${REQ_AVISOS[@]+"${REQ_AVISOS[@]}"}"; do info "AVISO: $a"; done
  return 0
}

req_plan() {
  local id total=0 mb
  info "Faltan estos requisitos y se van a instalar:"
  for id in "${REQ_FALTA[@]}"; do
    mb="$(req_mb "$id")"
    total=$((total + mb))
    if (( mb > 0 )); then
      info "  - $(req_nombre "$id")  (~${mb} MB)"
    else
      info "  - $(req_nombre "$id")"
    fi
  done
  info "Descarga total aproximada: ~$(( (total + 512) / 1024 )) GB. Se instalan en tu usuario salvo los paquetes del sistema, que piden sudo."
}

# --- instalar: base ------------------------------------------------------------------------------------
req_preparar_sudo() {
  [[ -n "$REQ_SUDO" || "$(id -u)" == "0" ]] && return 0
  if req_tiene sudo; then
    REQ_SUDO="sudo"
    info "Hace falta sudo para instalar paquetes del sistema; te pedira la contrasena."
    sudo -v || { mal "No se pudo obtener permisos de administrador (sudo)."; return 1; }
  else
    mal "Faltan paquetes del sistema y no hay 'sudo'. Corre este script como root o instala sudo."
    return 1
  fi
}

req_apt() {
  $REQ_SUDO env DEBIAN_FRONTEND=noninteractive LC_ALL=C apt-get -y -q "$@"
}

req_apt_disponible() { LC_ALL=C apt-cache show "$1" >/dev/null 2>&1; }

req_instalar_apt() {
  local paquetes=() id j lib
  for id in "${REQ_FALTA[@]}"; do
    if [[ "$id" == apt:* ]]; then paquetes+=("${id#apt:}"); fi
  done
  if req_en_falta jdk; then
    for j in openjdk-21-jdk-headless openjdk-17-jdk-headless; do
      if req_apt_disponible "$j"; then paquetes+=("$j"); break; fi
    done
  fi
  if req_en_falta kvm; then paquetes+=(acl); fi
  # Bibliotecas que el emulador necesita en un Linux minimo; si el nombre no existe en esta version, se omite.
  if req_quiere_emulador; then
    for lib in libpulse0 libgl1 libnss3 libxkbfile1; do
      if req_tiene dpkg && dpkg -s "$lib" >/dev/null 2>&1; then continue; fi
      if req_apt_disponible "$lib"; then paquetes+=("$lib"); fi
    done
  fi
  (( ${#paquetes[@]} )) || return 0
  paso "Instalando paquetes del sistema (${paquetes[*]})"
  req_preparar_sudo || return 1
  req_apt update || return 1
  req_apt install --no-install-recommends "${paquetes[@]}" || return 1
  REQ_INSTALADO=1
}

# --- instalar: Docker -------------------------------------------------------------------------------------
req_instalar_docker() {
  req_en_falta docker || req_en_falta compose || return 0
  paso "Instalando Docker"
  req_preparar_sudo || return 1
  local id codigo base nombre_repo
  # shellcheck disable=SC1091
  id="$( . /etc/os-release; printf '%s' "${ID:-}" )"
  case "$id" in ubuntu|debian) ;; *)
    # derivados (Mint, Pop!_OS...): se usa la base de la que vienen
    # shellcheck disable=SC1091
    id="$( . /etc/os-release; case "${ID_LIKE:-}" in *ubuntu*) echo ubuntu;; *) echo debian;; esac )" ;;
  esac
  # shellcheck disable=SC1091
  codigo="$( . /etc/os-release; printf '%s' "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}" )"
  base="https://download.docker.com/linux/$id"
  # Una version muy nueva del sistema puede no tener repo todavia: se usa la LTS/estable anterior.
  if ! curl -fsI "$base/dists/$codigo/Release" >/dev/null 2>&1; then
    nombre_repo="noble"; [[ "$id" == "debian" ]] && nombre_repo="bookworm"
    info "Docker aun no publica '$codigo'; se usa '$nombre_repo'."
    codigo="$nombre_repo"
  fi
  req_apt update || return 1
  req_apt install --no-install-recommends ca-certificates curl || return 1
  $REQ_SUDO install -m 0755 -d /etc/apt/keyrings || return 1
  $REQ_SUDO curl -fsSL "$base/gpg" -o /etc/apt/keyrings/docker.asc || return 1
  $REQ_SUDO chmod a+r /etc/apt/keyrings/docker.asc || return 1
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] %s %s stable\n' \
    "$(dpkg --print-architecture)" "$base" "$codigo" | $REQ_SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null || return 1
  req_apt update || return 1
  if req_en_falta docker; then
    req_apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return 1
  else
    req_apt install docker-compose-plugin || return 1
  fi
  # En un contenedor o WSL sin systemd el servicio no arranca: no es motivo para abortar.
  $REQ_SUDO systemctl enable --now docker >/dev/null 2>&1 \
    || info "No se pudo iniciar el servicio de Docker con systemd; se intentara mas adelante."
  req_agregar_a_grupo docker
  REQ_INSTALADO=1
}

req_en_grupo() { id -nG 2>/dev/null | tr ' ' '\n' | grep -qx "$1"; }

req_agregar_a_grupo() {
  local grupo="$1" usuario="${USER:-$(id -un)}"
  [[ "$(id -u)" == "0" ]] && return 0
  getent group "$grupo" >/dev/null 2>&1 || return 0
  if ! getent group "$grupo" | grep -qE "[:,]${usuario}(,|$)"; then
    $REQ_SUDO usermod -aG "$grupo" "$usuario"
    info "Se agrego a $usuario al grupo '$grupo'."
  fi
}

# Relanza el script con el grupo recien agregado, para no pedir que se cierre la sesion.
# Uso: req_relanzar_con_grupo <grupo> <comando> [args...]. Solo una vez (REQ_RELANZADO).
req_relanzar_con_grupo() {
  local grupo="$1"; shift
  [[ -n "${REQ_RELANZADO:-}" ]] && return 1
  req_tiene sg || return 1
  getent group "$grupo" | grep -qE "[:,]${USER:-$(id -un)}(,|$)" || return 1
  local cmd
  cmd="$(printf '%q ' "$@")"
  info "Continuando con el grupo '$grupo' activo..."
  REQ_RELANZADO=1 exec sg "$grupo" -c "REQ_RELANZADO=1 $cmd"
}

# --- instalar: Flutter, Android -----------------------------------------------------------------------------
req_descargar() {
  local url="$1" destino="$2" progreso="--silent"
  [[ -t 1 ]] && progreso="--progress-bar"
  curl -fL --retry 3 --retry-delay 2 "$progreso" -o "$destino" "$url"
}

req_verificar_sha256() {
  local real
  real="$(sha256sum "$1" | awk '{print $1}')"
  [[ "$real" == "$2" ]] || { mal "El sha256 de $(basename "$1") no coincide (esperado $2, real $real)."; return 1; }
}

# Falla antes de descargar si no hay lugar: mejor saberlo que quedarse a mitad de un tar.
req_hay_espacio() {
  local mb="$1" dir="$2" libre
  mkdir -p "$dir"
  libre="$(df -Pm "$dir" | awk 'NR==2 {print $4}')"
  if (( libre < mb )); then
    mal "No hay espacio suficiente en $dir: hacen falta ~${mb} MB y hay ${libre} MB libres."
    return 1
  fi
}

# Directorio temporal dentro del destino: /tmp suele ser un tmpfs chico y aca se bajan GB.
req_flutter_trabajo() {
  local tmp="$1" destino="$2"
  info "Descargando (~1,6 GB)..."
  req_descargar "$REQ_FLUTTER_URL_LINUX" "$tmp/flutter.tar.xz" || return 1
  req_verificar_sha256 "$tmp/flutter.tar.xz" "$REQ_FLUTTER_SHA256_LINUX" || return 1
  info "Descomprimiendo..."
  tar -xJf "$tmp/flutter.tar.xz" -C "$tmp" || return 1
  mv "$tmp/flutter" "$destino" || return 1
}

req_instalar_flutter() {
  req_en_falta flutter || return 0
  paso "Instalando Flutter $REQ_FLUTTER_VERSION"
  local tmp destino padre rc
  destino="$REQ_FLUTTER_DIR"; padre="$(dirname "$destino")"
  req_hay_espacio 4500 "$padre" || return 1
  if [[ -e "$destino" ]]; then
    mv "$destino" "$destino.incompleto-$(date +%Y%m%d%H%M%S)" || return 1
    info "Habia una carpeta de Flutter incompleta; quedo como $(basename "$destino").incompleto-*."
  fi
  tmp="$(mktemp -d -p "$padre")" || return 1
  req_flutter_trabajo "$tmp" "$destino"; rc=$?
  rm -rf "$tmp"
  (( rc == 0 )) || return 1
  export PATH="$destino/bin:$PATH"
  REQ_INSTALADO=1
  bien "Flutter $REQ_FLUTTER_VERSION instalado en $destino."
}

req_cmdline_trabajo() {
  local tmp="$1" sdk="$2"
  req_descargar "$REQ_CMDLINE_URL_LINUX" "$tmp/cmdline.zip" || return 1
  req_verificar_sha256 "$tmp/cmdline.zip" "$REQ_CMDLINE_SHA256_LINUX" || return 1
  unzip -q "$tmp/cmdline.zip" -d "$tmp" || return 1
  mkdir -p "$sdk/cmdline-tools" || return 1
  rm -rf "$sdk/cmdline-tools/latest"
  mv "$tmp/cmdline-tools" "$sdk/cmdline-tools/latest" || return 1
}

req_instalar_cmdline() {
  req_en_falta sdk-cmdline || return 0
  paso "Instalando las herramientas de linea de comandos de Android"
  local sdk tmp rc
  sdk="$(req_sdk_dir)"
  req_hay_espacio 3500 "$sdk" || return 1
  tmp="$(mktemp -d -p "$sdk")" || return 1
  req_cmdline_trabajo "$tmp" "$sdk"; rc=$?
  rm -rf "$tmp"
  (( rc == 0 )) || return 1
  REQ_INSTALADO=1
  bien "Herramientas instaladas en $sdk/cmdline-tools/latest."
}

# sdkmanager corre con el JDK: JAVA_HOME ya quedo apuntando a uno suficiente (req_buscar_jdk).
req_sdkmanager_correr() {
  local sdk mgr
  sdk="$(req_sdk_dir)"; mgr="$(req_sdkmanager)" || return 1
  "$mgr" --sdk_root="$sdk" "$@"
}

req_instalar_sdk() {
  if ! req_en_falta sdk-paquetes && ! req_en_falta emulador && ! req_en_falta imagen; then return 0; fi
  paso "Instalando el SDK de Android"
  local sdk paquetes=(platform-tools "$REQ_PLATAFORMA" "$REQ_BUILD_TOOLS")
  sdk="$(req_sdk_dir)"
  if req_quiere_emulador; then paquetes+=(emulator "$(req_imagen_sdk)"); fi
  info "Paquetes: ${paquetes[*]}"
  req_buscar_jdk || { mal "No hay un JDK ${REQ_JAVA_MINIMO}+ para correr sdkmanager."; return 1; }
  # Las licencias se aceptan con 'yes'; el estado de salida de 'yes' (SIGPIPE) no importa.
  { yes 2>/dev/null || true; } | req_sdkmanager_correr --licenses >/dev/null 2>&1 || true
  { yes 2>/dev/null || true; } | req_sdkmanager_correr "${paquetes[@]}" || {
    mal "sdkmanager no pudo instalar los paquetes."; return 1; }
  export ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="$sdk"
  export PATH="$sdk/cmdline-tools/latest/bin:$sdk/platform-tools:$sdk/emulator:$PATH"
  REQ_INSTALADO=1
}

req_crear_avd() {
  local nombre="${1:-$REQ_AVD_DEFECTO}" sdk imagen config avdm
  sdk="$(req_sdk_dir)"
  imagen="$(req_imagen_sdk)"
  if req_avd_existe "$nombre"; then return 0; fi
  avdm="$sdk/cmdline-tools/latest/bin/avdmanager"
  [[ -x "$avdm" ]] || avdm="$(command -v avdmanager || true)"
  [[ -n "$avdm" ]] || { mal "No encuentro avdmanager para crear el emulador."; return 1; }
  paso "Creando el emulador $nombre"
  req_buscar_jdk >/dev/null 2>&1 || true
  # avdmanager escribe quejas inofensivas (devices.xml) aunque cree el emulador: se juzga por el resultado.
  local salida
  salida="$(echo no | "$avdm" create avd --force -n "$nombre" -k "$imagen" -d pixel_5 2>&1)" || true
  if ! req_avd_existe "$nombre"; then
    mal "avdmanager no pudo crear $nombre:"
    printf '%s\n' "$salida" | sed 's/^/    /' >&2
    return 1
  fi
  config="$(req_avd_dir)/$nombre.avd/config.ini"
  # El Pixel 5 sale con poca memoria; con 2 GB la app corre sin arrastrarse.
  if [[ -f "$config" ]]; then
    sed -i '/^hw.ramSize=/d' "$config"
    echo 'hw.ramSize=2048' >> "$config"
  fi
  REQ_INSTALADO=1
  bien "Emulador $nombre creado."
}

req_configurar_kvm() {
  req_en_falta kvm || return 0
  paso "Dando acceso a KVM"
  req_preparar_sudo || return 1
  $REQ_SUDO usermod -aG kvm "${USER:-$(id -un)}" 2>/dev/null || true
  # Acceso inmediato (hasta el proximo reinicio); el grupo cubre las sesiones nuevas.
  if req_tiene setfacl; then
    $REQ_SUDO setfacl -m "u:${USER:-$(id -un)}:rw" /dev/kvm || true
  fi
  if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    bien "KVM accesible."
  else
    REQ_AVISOS+=("KVM aun no es accesible en esta sesion: cierra sesion y vuelve a entrar para que tome el grupo 'kvm'.")
  fi
}

req_configurar_flutter() {
  req_flutter_bin >/dev/null || return 0
  req_quiere_sdk || return 0
  local sdk
  sdk="$(req_sdk_dir)"
  [[ -d "$sdk" ]] || return 0
  # Que flutter use este SDK y este JDK aunque ANDROID_HOME no este en el entorno de otra terminal.
  flutter config --android-sdk "$sdk" >/dev/null 2>&1 || true
  [[ -n "${JAVA_HOME:-}" ]] && flutter config --jdk-dir "$JAVA_HOME" >/dev/null 2>&1 || true
}

# Bloque marcado en el rc del shell: asi 'flutter run' funciona tambien en otras terminales.
req_persistir_entorno() {
  (( REQ_INSTALADO )) || return 0
  local rc sdk inicio="# >>> Check-In-Obra >>>" fin="# <<< Check-In-Obra <<<"
  case "$(basename "${SHELL:-bash}")" in zsh) rc="$HOME/.zshrc" ;; *) rc="$HOME/.bashrc" ;; esac
  sdk="$(req_sdk_dir)"
  [[ -f "$rc" ]] && grep -qF "$inicio" "$rc" && return 0
  {
    printf '\n%s\n' "$inicio"
    printf 'export ANDROID_HOME="%s"\n' "$sdk"
    # shellcheck disable=SC2016  # se escribe literal: lo expande el shell del usuario
    printf 'export ANDROID_SDK_ROOT="$ANDROID_HOME"\n'
    [[ -n "${JAVA_HOME:-}" ]] && printf 'export JAVA_HOME="%s"\n' "$JAVA_HOME"
    # shellcheck disable=SC2016
    printf 'export PATH="%s/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"\n' "$REQ_FLUTTER_DIR"
    printf '%s\n' "$fin"
  } >> "$rc"
  info "Deje ANDROID_HOME y el PATH en $rc para tus otras terminales (abre una nueva o: source $rc)."
}

# --- punto de entrada ----------------------------------------------------------------------------------------
# Exporta al proceso lo que ya esta instalado (aunque no este en el PATH del usuario).
req_exportar_entorno() {
  local sdk
  sdk="$(req_sdk_dir)"
  [[ -x "$REQ_FLUTTER_DIR/bin/flutter" ]] && ! req_tiene flutter && export PATH="$REQ_FLUTTER_DIR/bin:$PATH"
  if [[ -d "$sdk" ]]; then
    export ANDROID_HOME="${ANDROID_HOME:-$sdk}" ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$sdk}"
    local d
    for d in "$sdk/cmdline-tools/latest/bin" "$sdk/platform-tools" "$sdk/emulator"; do
      [[ -d "$d" && ":$PATH:" != *":$d:"* ]] && PATH="$d:$PATH"
    done
    export PATH
  fi
}

# asegurar_requisitos: usa las variables de levantar.sh (instalar, comprobar, solo_instalar,
# sin_emulador, telefono). Sale del proceso con 'exit' cuando el modo es solo informar o instalar.
asegurar_requisitos() {
  req_exportar_entorno
  if ! req_es_debian; then
    if (( ${comprobar:-0} )); then
      info "La comprobacion de requisitos solo existe en Ubuntu/Debian; en este sistema cada herramienta se revisa al usarla."
      exit 0
    fi
    if (( ${solo_instalar:-0} )); then
      mal "--solo-instalar solo funciona en Ubuntu/Debian. Instala los requisitos a mano (README, 'Requisitos previos')."
      exit 1
    fi
    return 0
  fi
  req_detectar

  if (( ${comprobar:-0} )); then
    req_informe
    if (( ${#REQ_FALTA[@]} )); then
      info "Faltan ${#REQ_FALTA[@]} requisito(s). Corre sin --comprobar para instalarlos."
      exit 1
    fi
    bien "Todo presente."
    exit 0
  fi

  if (( ${#REQ_FALTA[@]} == 0 )); then
    req_configurar_flutter
    (( ${solo_instalar:-0} )) && { bien "Todo presente: no habia nada que instalar."; exit 0; }
    return 0
  fi

  if (( ! ${instalar:-1} )); then
    req_informe
    mal "Faltan requisitos y se pidio no instalarlos (--sin-instalar)."
    exit 1
  fi

  paso "Requisitos que faltan"
  req_plan
  req_instalar_apt        || exit 1
  req_instalar_docker     || exit 1
  # los paquetes recien instalados (JDK) tienen que estar a la vista antes de usar sdkmanager
  hash -r
  req_buscar_jdk || true
  req_instalar_flutter    || exit 1
  req_instalar_cmdline    || exit 1
  req_instalar_sdk        || exit 1
  req_configurar_kvm      || true
  if req_en_falta avd; then req_crear_avd || exit 1; fi
  req_configurar_flutter
  req_persistir_entorno
  local a
  for a in "${REQ_AVISOS[@]+"${REQ_AVISOS[@]}"}"; do info "AVISO: $a"; done
  bien "Requisitos instalados."
  (( ${solo_instalar:-0} )) && exit 0
  return 0
}
