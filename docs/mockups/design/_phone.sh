#!/bin/bash
# Chrome compartido de la app móvil de Check-In-Obra (390x844).

p_head() { # $1 = color de fondo del root (opcional, por defecto #F8FAFC)
  local bg="${1:-#F8FAFC}"
cat <<EOF
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fira+Code:wght@400;500;600;700&family=Fira+Sans:wght@300;400;500;600;700&display=swap">
  <style>
    * { box-sizing: border-box; }
    body { margin: 0; background: ${bg}; color: #334155; font-family: 'Fira Sans', system-ui, -apple-system, 'Segoe UI', sans-serif; -webkit-font-smoothing: antialiased; }
    a { color: #C2410C; text-decoration: none; }
    a:hover { color: #9A3412; }
    svg { display: block; }
  </style>
</helmet>

<div style="width: 390px; height: 844px; background: ${bg}; display: flex; flex-direction: column; overflow: hidden">

  <div style="height: 44px; background: #334155; flex-shrink: 0"></div>
EOF
}

p_backbar() { # $1 = título, $2 = html a la derecha (opcional)
cat <<EOF
  <div style="background: #334155; padding: 4px 8px 12px; display: flex; align-items: center; gap: 4px; flex-shrink: 0">
    <div style="display: flex; align-items: center; justify-content: center; width: 44px; height: 44px; cursor: pointer">
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M15 5.5 8.5 12l6.5 6.5"/></svg>
    </div>
    <span style="font-size: 17px; font-weight: 600; color: #FFFFFF; flex-grow: 1">$1</span>
    $2
  </div>
EOF
}

p_tabbar() { # $1 = pestaña activa: Inicio | Bodega | Herram | Alertas
  local act="$1"
  local names=(Inicio Bodega Herram Alertas)
  local labels=("Inicio" "Bodega" "Herram." "Alertas")
  local icons=(
    '<path d="M4 10.5 12 4l8 6.5V20a1 1 0 0 1-1 1h-4v-6H9v6H5a1 1 0 0 1-1-1v-9.5Z"/>'
    '<path d="M12 3 3 7.5v9L12 21l9-4.5v-9L12 3Z"/><path d="m3 7.5 9 4.5 9-4.5"/><path d="M12 12v9"/>'
    '<path d="M15.4 8.6a4.2 4.2 0 0 1-5.6 5.6l-4.6 4.6a2.1 2.1 0 0 1-3-3l4.6-4.6a4.2 4.2 0 0 1 5.6-5.6l-2.7 2.7 2.4 2.4 2.7-2.7a4.2 4.2 0 0 1 .6.6Z"/>'
    '<path d="M6 9.5a6 6 0 0 1 12 0c0 4.6 1.8 5.6 1.8 5.6H4.2S6 14.1 6 9.5Z"/><path d="M9.6 18.6a2.5 2.5 0 0 0 4.8 0"/>'
  )
  printf '  <div style="height: 78px; background: #FFFFFF; border-top: 1px solid #E2E8F0; display: flex; align-items: flex-start; padding: 8px 8px 0; flex-shrink: 0">\n'
  local i
  for i in 0 1; do
    p_tab "$act" "${names[$i]}" "${labels[$i]}" "${icons[$i]}"
  done
cat <<'EOF'
    <div style="flex-grow: 1; display: flex; justify-content: center; padding-top: 2px">
      <div style="display: flex; align-items: center; justify-content: center; width: 54px; height: 54px; background: #334155; cursor: pointer">
        <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><rect x="3.5" y="3.5" width="6.5" height="6.5"/><rect x="14" y="3.5" width="6.5" height="6.5"/><rect x="3.5" y="14" width="6.5" height="6.5"/><path d="M14 14h3v3h-3zM20.5 14v3.5M14 20.5h6.5"/></svg>
      </div>
    </div>
EOF
  for i in 2 3; do
    p_tab "$act" "${names[$i]}" "${labels[$i]}" "${icons[$i]}"
  done
  printf '  </div>\n'
}

p_tab() { # activo, nombre, etiqueta, paths
  local stroke="#64748B" w="1.75" col="#64748B" fw="500"
  if [ "$1" = "$2" ]; then stroke="#C2410C"; w="1.9"; col="#C2410C"; fw="600"; fi
  printf '    <div style="flex-grow: 1; display: flex; flex-direction: column; align-items: center; gap: 4px; padding: 6px 0; cursor: pointer">\n'
  printf '      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round">%s</svg>\n' "$stroke" "$w" "$4"
  printf '      <span style="font-size: 10px; font-weight: %s; color: %s">%s</span>\n' "$fw" "$col" "$3"
  printf '    </div>\n'
}

p_foot() {
cat <<'EOF'
</div>
</x-dc>
</body>
</html>
EOF
}
