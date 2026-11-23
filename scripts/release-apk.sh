#!/usr/bin/env bash
# Compila el APK de release firmado y ofuscado.
#
#   API_BASE_URL=https://api.checkinobra.cl \
#   CHECKINOBRA_KEYSTORE_FILE=/ruta/release.jks \
#   CHECKINOBRA_KEYSTORE_PASSWORD=... CHECKINOBRA_KEY_ALIAS=... \
#   CHECKINOBRA_KEY_PASSWORD=... \
#   scripts/release-apk.sh
#
# Opcional: API_CERT_SHA256=<huella> fija el certificado del servidor (varias,
# separadas por coma). Sin esa variable la app confía en el certificado como
# siempre; ver "Fijar el certificado" en mobile/README.md.
#
# En local, en vez de las cuatro variables del keystore puede usarse
# mobile/android/key.properties (no versionado). Nada de esto se escribe en el
# repo: el keystore y sus claves salen de variables de entorno o, en el CI, de
# los secretos del repositorio.
#
# Deja el APK en mobile/build/app/outputs/flutter-apk/ y los símbolos de
# depuración en mobile/build/debug-info/. Esos símbolos son lo único que permite
# leer un stack trace del APK ofuscado: guárdalos junto a cada versión que
# publiques, y no los distribuyas con la app.
set -euo pipefail

cd "$(dirname "$0")/../mobile"

if [[ -z "${API_BASE_URL:-}" ]]; then
  echo "Falta API_BASE_URL (la URL https:// de la API)." >&2
  exit 1
fi
if [[ "${API_BASE_URL}" != https://* ]]; then
  echo "API_BASE_URL tiene que empezar con https:// (recibí: ${API_BASE_URL})." >&2
  exit 1
fi

# Argumentos que solo se agregan si hay con qué: la fijación de certificado es
# opcional y, sin la variable, el build es el de siempre.
extra=()
if [[ -n "${API_CERT_SHA256:-}" ]]; then
  # Cada huella: 64 dígitos hexadecimales, con o sin ":" (lo que imprime
  # openssl). Una mal escrita dejaría la app sin poder arrancar en el teléfono.
  IFS=',' read -ra huellas <<< "${API_CERT_SHA256}"
  for huella in "${huellas[@]}"; do
    huella="${huella//[[:space:]]/}"
    [[ -z "$huella" ]] && continue
    if [[ ! "${huella//:/}" =~ ^[0-9A-Fa-f]{64}$ ]]; then
      echo "API_CERT_SHA256 tiene una huella mal formada: '${huella}'." >&2
      echo "Cada una es el SHA-256 del certificado: 64 dígitos hexadecimales." >&2
      exit 1
    fi
  done
  extra+=(--dart-define=API_CERT_SHA256="${API_CERT_SHA256}")
  echo "Fijación de certificado activada (${#huellas[@]} huella/s)."
fi

flutter build apk --release \
  --obfuscate \
  --split-debug-info=build/debug-info \
  --dart-define=API_BASE_URL="${API_BASE_URL}" \
  ${extra[@]+"${extra[@]}"}
