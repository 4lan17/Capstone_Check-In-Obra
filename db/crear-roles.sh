#!/usr/bin/env bash
# Crea (o sincroniza) los roles checkinobra_app y checkinobra_migrador. Ver roles.sql.
#
# Se usa de tres maneras:
#   1. Base nueva: docker-compose lo monta en /docker-entrypoint-initdb.d y el
#      entrypoint de Postgres lo corre una sola vez, al crear el volumen.
#   2. Base existente (volumen anterior a esto):
#        docker compose exec -T db /docker-entrypoint-initdb.d/01-roles.sh
#      scripts/levantar.sh lo hace solo.
#   3. Fuera de Docker o en CI: con PGHOST, PGUSER, PGPASSWORD y PGDATABASE del
#      superusuario, y CHECKINOBRA_APP_PASSWORD / CHECKINOBRA_MIGRADOR_PASSWORD.
#
# No imprime las contraseñas y se niega a seguir si falta alguna.
set -euo pipefail

: "${CHECKINOBRA_APP_PASSWORD:?Falta CHECKINOBRA_APP_PASSWORD (DB_APP_PASSWORD en el .env)}"
: "${CHECKINOBRA_MIGRADOR_PASSWORD:?Falta CHECKINOBRA_MIGRADOR_PASSWORD (DB_MIGRADOR_PASSWORD en el .env)}"

sql="${ROLES_SQL:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/roles.sql}"
[[ -f "$sql" ]] || { echo "No encuentro $sql (defina ROLES_SQL)" >&2; exit 1; }

# Dentro del contenedor el superusuario viene en POSTGRES_USER / POSTGRES_DB.
export PGUSER="${PGUSER:-${POSTGRES_USER:-postgres}}"
export PGDATABASE="${PGDATABASE:-${POSTGRES_DB:-checkinobra}}"

psql -X -q -v ON_ERROR_STOP=1 \
  -v app_password="$CHECKINOBRA_APP_PASSWORD" \
  -v migrador_password="$CHECKINOBRA_MIGRADOR_PASSWORD" \
  -f "$sql"
echo "Roles checkinobra_app y checkinobra_migrador listos."
