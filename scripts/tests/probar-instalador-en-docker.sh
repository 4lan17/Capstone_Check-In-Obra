#!/usr/bin/env bash
# Prueba el instalador de requisitos DE VERDAD en un contenedor limpio de Ubuntu o Debian: un usuario
# normal con sudo, sin nada instalado, corre 'levantar.sh --solo-instalar' y despues se comprueba que
# quedaron Flutter, el SDK de Android, el AVD, el JDK y Docker (los paquetes).
#
#   scripts/tests/probar-instalador-en-docker.sh                  # ubuntu:24.04
#   scripts/tests/probar-instalador-en-docker.sh debian:12        # otra imagen
#
# Descarga del orden de 3 a 4 GB (Flutter, SDK, imagen del emulador) y tarda varios minutos.
# Limites de un contenedor: no hay systemd (el servicio de Docker no arranca; el instalador lo tolera) ni
# /dev/kvm (el emulador no se puede arrancar, pero su AVD si se crea). Lo demas es la instalacion real.
set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
imagen="${1:-ubuntu:24.04}"

echo "== Imagen: $imagen =="
docker run --rm -v "$raiz/scripts:/origen/scripts:ro" "$imagen" \
  bash /origen/scripts/tests/dentro-del-contenedor.sh root
echo "== OK: el instalador funciona en $imagen =="
