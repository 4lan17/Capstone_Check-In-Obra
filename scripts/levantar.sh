#!/usr/bin/env bash
# Deja Check-In-Obra andando para desarrollar: enciende Docker Desktop si esta
# apagado, construye y levanta las imagenes, y arranca un emulador de Android.
# El emulador parte primero y bootea mientras Docker construye, que es lo que
# mas tarda.
#
#   scripts/levantar.sh                 # Docker Desktop + imagenes + emulador
#   scripts/levantar.sh --app           # ademas corre la app en el emulador (flutter run)
#   scripts/levantar.sh --sin-cache     # reconstruye las imagenes desde cero
#   scripts/levantar.sh --sin-emulador  # solo Docker
#   scripts/levantar.sh --avd NOMBRE    # otro emulador (por defecto Check-In-Obra_Pixel5)
#   scripts/levantar.sh --telefono      # en vez del emulador, corre la app en el telefono
#                                       # conectado por USB, con la API por adb reverse
#
# Con varios telefonos conectados: TELEFONO=<serie> scripts/levantar.sh --telefono
# (la serie sale de 'adb devices').
# En Windows usar scripts\levantar.ps1.
set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$raiz"

API="http://localhost:8081"
# El backend no tiene actuator; que publique su OpenAPI significa que arranco
# y que Flyway ya corrio.
SONDA="$API/v3/api-docs"
ESPERA_DOCKER=180     # segundos para que Docker Desktop responda
ESPERA_API=240        # la primera vez compila la imagen entera
ESPERA_EMULADOR=240
PUERTO_EMULADOR=5554
DISPOSITIVO="emulator-$PUERTO_EMULADOR"
LOG_EMULADOR="${TMPDIR:-/tmp}/checkinobra-emulador.log"

avd="${AVD:-}"
correr_app=0
sin_cache=0
sin_emulador=0
telefono=0
serie_telefono="${TELEFONO:-}"

# --- salida ---------------------------------------------------------------
if [[ -t 1 ]]; then
  TITULO=$'\x1b[1;36m'; OK=$'\x1b[32m'; MAL=$'\x1b[31m'; GRIS=$'\x1b[2m'; FIN=$'\x1b[0m'
else
  TITULO=""; OK=""; MAL=""; GRIS=""; FIN=""
fi
paso() { printf '\n%s%s%s\n' "$TITULO" "$1" "$FIN"; }
info() { printf '  %s\n' "$1"; }
bien() { printf '  %s%s%s\n' "$OK" "$1" "$FIN"; }
mal()  { printf '  %s%s%s\n' "$MAL" "$1" "$FIN" >&2; }

uso() {
  awk 'NR>1 { if (/^#/) { sub(/^# ?/, ""); print } else { exit } }' "${BASH_SOURCE[0]}"
  exit "${1:-0}"
}

# --- argumentos -----------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)          correr_app=1 ;;
    --sin-cache)    sin_cache=1 ;;
    --sin-emulador) sin_emulador=1 ;;
    --telefono)     telefono=1 ;;
    --avd)          shift; avd="${1:?--avd necesita un nombre}" ;;
    -h|--help)      uso ;;
    *) printf 'Opcion desconocida: %s\n\n' "$1" >&2; uso 1 >&2 ;;
  esac
  shift
done
if (( telefono )); then
  if [[ -n "$avd" ]]; then
    mal "--telefono no usa emulador: no se puede combinar con --avd."
    exit 1
  fi
  # El telefono reemplaza al emulador, y la app siempre se corre en el.
  sin_emulador=1
  correr_app=0
elif (( correr_app && sin_emulador )); then
  mal "--app necesita el emulador: no se puede combinar con --sin-emulador."
  exit 1
fi

# --- herramientas ---------------------------------------------------------
for cmd in docker curl; do
  command -v "$cmd" >/dev/null || { mal "Falta '$cmd' en el PATH."; exit 1; }
done

# emulator y adb suelen no estar en el PATH aunque el SDK este instalado:
# Android Studio no los agrega. Se buscan en las rutas de siempre.
buscar_sdk() {
  local candidato
  for candidato in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" \
                   "$HOME/Android/Sdk" "$HOME/Library/Android/sdk"; do
    if [[ -n "$candidato" && -d "$candidato/emulator" ]]; then
      printf '%s' "$candidato"
      return 0
    fi
  done
  return 1
}

necesarios=()
(( ! sin_emulador )) && necesarios+=(emulator adb)
(( telefono )) && necesarios+=(adb)
if ((${#necesarios[@]})); then
  if ! command -v emulator >/dev/null || ! command -v adb >/dev/null; then
    if sdk="$(buscar_sdk)"; then
      PATH="$sdk/emulator:$sdk/platform-tools:$PATH"
    fi
  fi
  for cmd in "${necesarios[@]}"; do
    command -v "$cmd" >/dev/null || {
      mal "No se encontro '$cmd'. Instala el SDK de Android o define ANDROID_HOME."
      info "Para seguir solo con Docker: scripts/levantar.sh --sin-emulador"
      exit 1
    }
  done
fi
if (( correr_app || telefono )); then
  command -v flutter >/dev/null || { mal "Falta 'flutter' en el PATH."; exit 1; }
fi

# --- 0. telefono -----------------------------------------------------------
# Se busca antes de tocar Docker: si el telefono no esta autorizado, mejor
# saberlo ahora y no despues de construir la imagen.
elegir_telefono() {
  local lineas listos pendientes
  lineas="$(adb devices 2>/dev/null | tail -n +2 | tr -d '\r' | grep -v '^emulator-' | grep -v '^$' || true)"
  listos="$(awk '$2 == "device" { print $1 }' <<<"$lineas")"
  pendientes="$(awk '$2 == "unauthorized" { print $1 }' <<<"$lineas")"

  if [[ -n "$serie_telefono" ]]; then
    if grep -qx "$serie_telefono" <<<"$listos"; then
      return 0
    fi
    mal "El telefono '$serie_telefono' no esta conectado y autorizado."
    return 1
  fi

  if [[ -z "$listos" ]]; then
    if [[ -n "$pendientes" ]]; then
      mal "El telefono $(head -n1 <<<"$pendientes") esta conectado pero no autorizado."
      info "Desbloquealo y acepta 'Permitir depuracion USB' (marca 'Permitir siempre')."
      info "Si el aviso no aparece, desconecta y vuelve a conectar el cable."
    else
      mal "No hay ningun telefono conectado."
      info "Conectalo por USB con la 'Depuracion USB' activada en Opciones de desarrollador."
      info "Debe aparecer como 'device' en: adb devices"
    fi
    return 1
  fi

  if (( $(wc -l <<<"$listos") > 1 )); then
    mal "Hay mas de un telefono conectado:"
    sed 's/^/    /' <<<"$listos" >&2
    info "Elige uno: TELEFONO=<serie> scripts/levantar.sh --telefono"
    return 1
  fi
  serie_telefono="$listos"
}

if (( telefono )); then
  paso "Telefono"
  adb start-server >/dev/null 2>&1 || true
  elegir_telefono || exit 1
  modelo="$(adb -s "$serie_telefono" shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
  bien "$serie_telefono${modelo:+ ($modelo)} conectado."
fi

# --- 1. emulador (en segundo plano) ----------------------------------------
emulador_corriendo() { adb devices 2>/dev/null | grep -q "^${DISPOSITIVO}[[:space:]]"; }

elegir_avd() {
  local disponibles
  disponibles="$(emulator -list-avds 2>/dev/null | tr -d '\r')"
  if [[ -z "$disponibles" ]]; then
    mal "No hay ningun emulador creado."
    info "Crea uno en Android Studio (Device Manager) o con 'flutter emulators --create'."
    return 1
  fi
  if [[ -n "$avd" ]]; then
    grep -qx "$avd" <<<"$disponibles" || {
      mal "No existe el emulador '$avd'. Los disponibles son:"
      sed 's/^/    /' <<<"$disponibles" >&2
      return 1
    }
  elif grep -qx "Check-In-Obra_Pixel5" <<<"$disponibles"; then
    avd="Check-In-Obra_Pixel5"
  else
    avd="$(head -n1 <<<"$disponibles")"
  fi
}

if (( ! sin_emulador )); then
  paso "Emulador"
  adb start-server >/dev/null 2>&1 || true
  if emulador_corriendo; then
    bien "$DISPOSITIVO ya estaba corriendo."
  else
    elegir_avd || exit 1
    info "Arrancando $avd; bootea mientras se levanta Docker."
    # nohup + un proceso propio: el emulador sigue vivo cuando este script
    # termina o cuando se cierra la terminal.
    if command -v setsid >/dev/null; then
      setsid nohup emulator -avd "$avd" -port "$PUERTO_EMULADOR" \
        -netdelay none -netspeed full >"$LOG_EMULADOR" 2>&1 < /dev/null &
    else
      nohup emulator -avd "$avd" -port "$PUERTO_EMULADOR" \
        -netdelay none -netspeed full >"$LOG_EMULADOR" 2>&1 < /dev/null &
    fi
    disown || true
    info "${GRIS}Log del emulador: $LOG_EMULADOR${FIN}"
  fi
fi

# --- 2. Docker Desktop -----------------------------------------------------
docker_responde() { docker info >/dev/null 2>&1; }

encender_docker_desktop() {
  case "$(uname -s)" in
    Linux)
      if systemctl --user cat docker-desktop.service >/dev/null 2>&1; then
        systemctl --user start docker-desktop
      elif [[ -x /opt/docker-desktop/bin/docker-desktop ]]; then
        nohup /opt/docker-desktop/bin/docker-desktop >/dev/null 2>&1 < /dev/null &
        disown || true
      else
        mal "Docker no responde y no se encontro Docker Desktop."
        info "Si usas Docker Engine sin Desktop: sudo systemctl start docker"
        return 1
      fi
      ;;
    Darwin)
      open -a Docker
      ;;
    MINGW*|MSYS*|CYGWIN*)
      "/c/Program Files/Docker/Docker/Docker Desktop.exe" >/dev/null 2>&1 &
      ;;
    *)
      mal "No se como encender Docker Desktop en $(uname -s). Abrelo a mano."
      return 1
      ;;
  esac
}

paso "Docker Desktop"
if docker_responde; then
  bien "Ya estaba encendido."
else
  info "Encendiendo Docker Desktop..."
  encender_docker_desktop || exit 1
  limite=$((SECONDS + ESPERA_DOCKER))
  until docker_responde; do
    if (( SECONDS > limite )); then
      mal "Docker Desktop no respondio en ${ESPERA_DOCKER}s."
      info "Contexto activo: $(docker context show 2>/dev/null || echo '?')."
      info "Docker Desktop usa el contexto 'desktop-linux' en Linux y 'desktop-windows' o 'default' en Windows."
      exit 1
    fi
    sleep 3
  done
  bien "Docker Desktop responde (contexto $(docker context show 2>/dev/null))."
fi

# --- 2b. secreto JWT ----------------------------------------------------------
# La API no arranca sin JWT_SECRET (ni con el valor de ejemplo) y compose lo
# lee del .env de la raiz, que no se versiona. Se genera una sola vez y no se
# imprime.
paso "Secreto JWT"
if grep -Eq '^JWT_SECRET=[^[:space:]]{32,}$' .env 2>/dev/null \
   && ! grep -Eiq '^JWT_SECRET=cambiar' .env; then
  bien "JWT_SECRET ya definido en .env."
else
  secreto="$(head -c 48 /dev/urandom | base64 | tr -d '\n')"
  [[ -f .env ]] && sed -i.bak '/^JWT_SECRET=/d' .env && rm -f .env.bak
  printf 'JWT_SECRET=%s\n' "$secreto" >> .env
  unset secreto
  bien "Generado un JWT_SECRET nuevo en .env (no se versiona)."
fi

# --- 3. imagenes y contenedores --------------------------------------------
paso "Construyendo las imagenes"
if (( sin_cache )); then
  docker compose build --no-cache
else
  docker compose build
fi

paso "Levantando los contenedores"
docker compose up -d

paso "Esperando que la API responda"
limite=$((SECONDS + ESPERA_API))
until curl -fsS -o /dev/null "$SONDA" 2>/dev/null; do
  if (( SECONDS > limite )); then
    mal "La API no respondio en ${ESPERA_API}s. Ultimas lineas del backend:"
    docker compose logs --tail=30 backend >&2 || true
    exit 1
  fi
  sleep 2
done
bien "La API responde en $API"

# --- 4. esperar el emulador ------------------------------------------------
if (( ! sin_emulador )); then
  paso "Esperando que el emulador termine de bootear"
  limite=$((SECONDS + ESPERA_EMULADOR))
  until [[ "$(adb -s "$DISPOSITIVO" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
    if (( SECONDS > limite )); then
      mal "$DISPOSITIVO no termino de bootear en ${ESPERA_EMULADOR}s."
      info "Revisa $LOG_EMULADOR. Si dice que falta KVM: sudo usermod -aG kvm \$USER y vuelve a entrar."
      exit 1
    fi
    sleep 2
  done
  bien "$DISPOSITIVO listo."
fi

# --- 4b. el telefono alcanza la API por el cable --------------------------
# adb reverse publica el 8081 del computador como localhost:8081 del telefono:
# no importa la WiFi ni la IP. Se pierde al desconectar el cable.
if (( telefono )); then
  paso "Conectando el telefono con la API"
  adb -s "$serie_telefono" reverse tcp:8081 tcp:8081 >/dev/null || {
    mal "No se pudo hacer adb reverse en $serie_telefono."
    exit 1
  }
  bien "localhost:8081 del telefono llega a la API del computador."
fi

# La app lee la URL de la API de mobile/.env. Sin ese archivo igual arranca,
# pero conviene que exista para que quien lo edite sepa donde esta.
if [[ ! -f mobile/.env ]]; then
  cp mobile/.env.example mobile/.env
  info "Creado mobile/.env desde .env.example (API_BASE_URL=http://10.0.2.2:8081)."
fi

# --- resumen ---------------------------------------------------------------
paso "Listo"
info "API          $API"
info "Swagger      $API/swagger-ui.html"
info "PostgreSQL   localhost:5433  (postgres / postgres)"
info "Admin        admin@arauco-ltda.cl  PIN 0000"
if (( ! sin_emulador )); then
  info "Emulador     $DISPOSITIVO"
fi
if (( telefono )); then
  info "Telefono     $serie_telefono"
fi
info "${GRIS}Cuentas de los cuatro roles: python3 scripts/cuentas_de_prueba.py${FIN}"
info "${GRIS}Bajar todo:                  docker compose down${FIN}"

if (( telefono )); then
  paso "Corriendo la app en $serie_telefono"
  cd mobile
  flutter pub get
  # La URL va al compilar y gana sobre mobile/.env (ver AppConfig), asi el
  # .env de cada quien queda como esta.
  exec flutter run -d "$serie_telefono" --dart-define=API_BASE_URL="$API"
elif (( correr_app )); then
  paso "Corriendo la app en $DISPOSITIVO"
  cd mobile
  flutter pub get
  exec flutter run -d "$DISPOSITIVO"
elif (( ! sin_emulador )); then
  info "${GRIS}Correr la app:               cd mobile && flutter run -d $DISPOSITIVO${FIN}"
fi
