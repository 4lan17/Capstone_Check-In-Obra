#!/usr/bin/env bash
# Lo corre probar-instalador-en-docker.sh dentro del contenedor; no esta pensado para usarse suelto.
set -euo pipefail

case "${1:-}" in
  root)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null
    # Lo unico que trae un equipo recien instalado: sudo (para el usuario) y curl (para bajar cosas).
    apt-get install -y -qq sudo ca-certificates curl >/dev/null
    useradd -m -s /bin/bash dev
    echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev
    exec su dev -c "bash /origen/scripts/tests/dentro-del-contenedor.sh usuario"
    ;;
  usuario)
    mkdir -p "$HOME/repo/mobile"
    cp -r /origen/scripts "$HOME/repo/scripts"
    : > "$HOME/repo/mobile/.env.example"
    cd "$HOME/repo"
    export ANDROID_HOME="$HOME/Android/Sdk"

    echo; echo "--- 1. --comprobar: debe fallar y listar lo que falta"
    if scripts/levantar.sh --comprobar; then echo "ERROR: --comprobar deberia salir con 1"; exit 1; fi

    echo; echo "--- 2. --solo-instalar: instala todo"
    scripts/levantar.sh --solo-instalar

    echo; echo "--- 3. segunda corrida: idempotente, no debe instalar nada"
    salida="$(scripts/levantar.sh --solo-instalar)"
    echo "$salida"
    grep -q "no habia nada que instalar" <<<"$salida"

    echo; echo "--- 4. --comprobar: ahora todo presente"
    scripts/levantar.sh --comprobar

    echo; echo "--- 5. verificacion independiente"
    printf 'flutter:  '; "$HOME/development/flutter/bin/flutter" --version 2>/dev/null | head -n1
    printf 'java:     '; java -version 2>&1 | head -n1
    printf 'docker:   '; docker --version
    printf 'compose:  '; docker compose version
    echo "paquetes del SDK:"
    "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --list_installed 2>/dev/null \
      | awk -F'|' 'NR>3 && NF>1 {gsub(/ /,"",$1); print "   " $1}'
    echo "AVD:"
    "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" list avd 2>/dev/null | grep -E "Name:|Device:" | sed 's/^/   /'
    printf 'bloque en ~/.bashrc: '; grep -c "Check-In-Obra" "$HOME/.bashrc"
    echo; echo "flutter doctor (Android toolchain):"
    "$HOME/development/flutter/bin/flutter" doctor -v 2>&1 | sed -n '/Android toolchain/,/^\[/p' | head -n 14
    ;;
  *)
    echo "uso interno: dentro-del-contenedor.sh root|usuario" >&2
    exit 1
    ;;
esac
