#!/bin/bash
# Emite las partes comunes del panel web de Check-In-Obra.
emit_head() {
cat <<'EOF'
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
    body { margin: 0; background: #F8FAFC; color: #334155; font-family: 'Fira Sans', system-ui, -apple-system, 'Segoe UI', sans-serif; -webkit-font-smoothing: antialiased; }
    a { color: #C2410C; text-decoration: none; }
    a:hover { color: #9A3412; }
    svg { display: block; }
  </style>
</helmet>

<div style="width: 1440px; height: 900px; background: #F8FAFC; display: flex; overflow: hidden">
EOF
}

# $1 = nombre del ítem activo, $2 = rol mostrado, $3 = iniciales, $4 = nombre usuario
emit_sidebar() {
  local active="$1" rol="$2" ini="$3" nom="$4"
  local names=(Panel Cubicacion Presupuesto Inventario Herramientas Cuadrillas Alertas Configuracion)
  local labels=("Panel de obra" "Cubicación" "Presupuesto" "Inventario" "Herramientas" "Cuadrillas" "Alertas" "Configuración")
  local icons=(
    '<path d="M4 20V4M4 20h16"/><path d="M8.5 20v-5.5M13 20v-9.5M17.5 20v-3.5"/>'
    '<path d="M3 14.6 14.6 3l6.4 6.4L9.4 21 3 14.6Z"/><path d="m7 12 2 2M10 9l2 2M13 6l2 2"/>'
    '<path d="M5 3.5h14v17l-2.5-1.6-2.5 1.6-2-1.4-2 1.4L7.5 18.9 5 20.5v-17Z"/><path d="M8.8 8.6h6.4M8.8 12.6h6.4"/>'
    '<path d="M12 3 3 7.5v9L12 21l9-4.5v-9L12 3Z"/><path d="m3 7.5 9 4.5 9-4.5"/><path d="M12 12v9"/>'
    '<path d="M15.4 8.6a4.2 4.2 0 0 1-5.6 5.6l-4.6 4.6a2.1 2.1 0 0 1-3-3l4.6-4.6a4.2 4.2 0 0 1 5.6-5.6l-2.7 2.7 2.4 2.4 2.7-2.7a4.2 4.2 0 0 1 .6.6Z"/>'
    '<circle cx="9.2" cy="8" r="3.4"/><path d="M3 19.2a6.2 6.2 0 0 1 12.4 0"/><path d="M16.2 5.2a3.4 3.4 0 0 1 0 5.6M17.6 13.4A6.2 6.2 0 0 1 21 19.2"/>'
    '<path d="M6 9.5a6 6 0 0 1 12 0c0 4.6 1.8 5.6 1.8 5.6H4.2S6 14.1 6 9.5Z"/><path d="M9.6 18.6a2.5 2.5 0 0 0 4.8 0"/>'
    '<circle cx="12" cy="12" r="3.1"/><path d="M12 3v2.4M12 18.6V21M3 12h2.4M18.6 12H21M5.6 5.6l1.7 1.7M16.7 16.7l1.7 1.7M18.4 5.6l-1.7 1.7M7.3 16.7l-1.7 1.7"/>'
  )
cat <<'EOF'
  <div style="width: 248px; background: #334155; display: flex; flex-direction: column; flex-shrink: 0">
    <div style="padding: 24px 20px 20px; display: flex; align-items: center; gap: 11px; border-bottom: 1px solid #475569">
      <div style="display: flex; align-items: center; justify-content: center; width: 32px; height: 32px; background: #EA580C; flex-shrink: 0">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20V8.5L12 3l8 5.5V20H4Z"/><path d="M9.5 20v-6h5v6"/></svg>
      </div>
      <span style="font-size: 17px; font-weight: 600; letter-spacing: -0.01em; color: #FFFFFF">Check-In-Obra</span>
    </div>

    <div style="padding: 16px 16px 10px; display: flex; flex-direction: column; gap: 7px">
      <span style="font-size: 10px; font-weight: 600; letter-spacing: 0.12em; text-transform: uppercase; color: #94A3B8">Obra</span>
      <div style="display: flex; align-items: center; gap: 8px; height: 44px; padding: 0 12px; background: #1E293B; border: 1px solid #475569; cursor: pointer">
        <span style="font-size: 13.5px; font-weight: 500; color: #FFFFFF; flex-grow: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis">Los Almendros · Torre B</span>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#94A3B8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink: 0"><path d="m6 9.5 6 6 6-6"/></svg>
      </div>
    </div>

    <div style="padding: 10px 12px; display: flex; flex-direction: column; gap: 2px; flex-grow: 1">
EOF
  local i
  for i in "${!names[@]}"; do
    if [ "${names[$i]}" = "$active" ]; then
      printf '      <div style="display: flex; align-items: center; gap: 12px; height: 42px; padding: 0 12px; background: #EA580C; cursor: pointer">\n'
      printf '        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">%s</svg>\n' "${icons[$i]}"
      printf '        <span style="font-size: 13.5px; font-weight: 600; color: #FFFFFF; flex-grow: 1">%s</span>\n' "${labels[$i]}"
    else
      printf '      <div style="display: flex; align-items: center; gap: 12px; height: 42px; padding: 0 12px; cursor: pointer">\n'
      printf '        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#94A3B8" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">%s</svg>\n' "${icons[$i]}"
      printf '        <span style="font-size: 13.5px; font-weight: 500; color: #CBD5E1; flex-grow: 1">%s</span>\n' "${labels[$i]}"
    fi
    if [ "${names[$i]}" = "Alertas" ]; then
      printf '        <span style="min-width: 20px; height: 20px; padding: 0 6px; background: #DC2626; color: #FFFFFF; font-family: %s; font-size: 10.5px; font-weight: 600; display: flex; align-items: center; justify-content: center">4</span>\n' "'Fira Code', monospace"
    fi
    printf '      </div>\n'
  done
cat <<EOF
    </div>

    <div style="padding: 16px; border-top: 1px solid #475569; display: flex; align-items: center; gap: 11px">
      <div style="display: flex; align-items: center; justify-content: center; width: 36px; height: 36px; background: #475569; flex-shrink: 0"><span style="font-size: 13px; font-weight: 600; color: #FFFFFF">${ini}</span></div>
      <div style="display: flex; flex-direction: column; gap: 2px; min-width: 0">
        <span style="font-size: 13px; font-weight: 500; color: #FFFFFF; white-space: nowrap; overflow: hidden; text-overflow: ellipsis">${nom}</span>
        <span style="font-size: 10px; font-weight: 600; letter-spacing: 0.06em; color: #94A3B8">${rol}</span>
      </div>
    </div>
  </div>

  <div style="flex-grow: 1; display: flex; flex-direction: column; min-width: 0">
EOF
}

emit_foot() {
cat <<'EOF'
  </div>
</div>
</x-dc>
</body>
</html>
EOF
}

emit_config_tabs() { # $1 = pestaña activa
  local active="$1"
  printf '      <div style="display: flex; align-items: center; gap: 2px; border-bottom: 1px solid #E2E8F0">\n'
  local t
  for t in "Empresa" "Usuarios y roles" "Materiales" "Parámetros de merma" "Obras"; do
    if [ "$t" = "$active" ]; then
      printf '        <div style="display: flex; align-items: center; height: 42px; padding: 0 16px; border-bottom: 3px solid #EA580C; cursor: pointer"><span style="font-size: 13.5px; font-weight: 600; color: #334155; white-space: nowrap">%s</span></div>\n' "$t"
    else
      printf '        <div style="display: flex; align-items: center; height: 42px; padding: 0 16px; border-bottom: 3px solid transparent; cursor: pointer"><span style="font-size: 13.5px; font-weight: 500; color: #64748B; white-space: nowrap">%s</span></div>\n' "$t"
    fi
  done
  printf '      </div>\n'
}
