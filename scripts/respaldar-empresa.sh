#!/usr/bin/env bash
# Respalda la base de UNA empresa con pg_dump (MT8, #111).
#
# Cada empresa tiene su propia base, así que el respaldo y la restauración son por empresa: el
# archivo de una constructora no contiene ningún dato de otra. Es un trabajo aparte de la API
# (la imagen del backend no trae pg_dump): se corre desde donde estén las herramientas de PostgreSQL.
#
# Uso:    scripts/respaldar-empresa.sh <nombre_de_la_base> [directorio]
# Ejemplo: scripts/respaldar-empresa.sh checkinobra_e764123309 ./respaldos
#
# El nombre de la base está en el catálogo (columna empresas.nombre_base) o en
#   GET /api/plataforma/empresas  (con el id de la empresa, para buscarla en el catálogo).
#
# Variables:
#   CHECKINOBRA_MIGRADOR_PASSWORD  contraseña de checkinobra_migrador (DB_MIGRADOR_PASSWORD del .env). Obligatoria.
#   PGHOST / PGPORT                dónde está el servidor (por defecto localhost:5432)
#   PG_PREFIX                      comando que antecede a las herramientas, para correrlas dentro del
#                                  contenedor de la base:  PG_PREFIX="docker compose exec -T db"
#
# El archivo queda en formato custom (-Fc), sin dueños ni permisos (la restauración los pone), con
# modo 600, y se verifica listando su contenido. No imprime contraseñas.
set -Eeuo pipefail

base="${1:?Uso: respaldar-empresa.sh <nombre_de_la_base> [directorio]}"
directorio="${2:-./respaldos}"
: "${CHECKINOBRA_MIGRADOR_PASSWORD:?Falta CHECKINOBRA_MIGRADOR_PASSWORD (DB_MIGRADOR_PASSWORD en el .env)}"

[[ "$base" =~ ^[a-z][a-z0-9_]{2,40}$ ]] || { echo "Nombre de base no válido: $base" >&2; exit 2; }

host="${PGHOST:-localhost}"
puerto="${PGPORT:-5432}"
prefijo="${PG_PREFIX:-}"

# Corre una herramienta de PostgreSQL con la contraseña en el entorno del proceso, no en sus argumentos
# (salvo con PG_PREFIX, donde `env` la pasa al contenedor).
pg() {
  if [[ -n "$prefijo" ]]; then
    # shellcheck disable=SC2086
    $prefijo env PGPASSWORD="$CHECKINOBRA_MIGRADOR_PASSWORD" "$@"
  else
    PGPASSWORD="$CHECKINOBRA_MIGRADOR_PASSWORD" "$@"
  fi
}

umask 077
mkdir -p "$directorio"
archivo="$directorio/${base}-$(date +%Y%m%d-%H%M%S).dump"

if ! pg pg_dump -Fc --no-owner --no-acl -h "$host" -p "$puerto" -U checkinobra_migrador "$base" > "$archivo.parcial"; then
  rm -f "$archivo.parcial"
  echo "No se pudo respaldar la base $base." >&2
  exit 1
fi
mv "$archivo.parcial" "$archivo"

# Un archivo que pg_restore no puede leer no es un respaldo.
if ! pg pg_restore -l < "$archivo" > /dev/null; then
  rm -f "$archivo"
  echo "El respaldo de $base salió ilegible y se descartó." >&2
  exit 1
fi
echo "$archivo"
