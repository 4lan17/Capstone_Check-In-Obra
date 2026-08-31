#!/usr/bin/env bash
# Enlaza las skills versionadas de .agents/skills/ hacia .claude/skills/,
# que es donde Claude Code las descubre. Como .claude/ está en .gitignore,
# cada quien corre esto una vez despues de clonar.
set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
origen="$raiz/.agents/skills"
destino="$raiz/.claude/skills"

mkdir -p "$destino"

# Limpia symlinks rotos de skills que ya no existen
find "$destino" -maxdepth 1 -xtype l -delete

for skill in "$origen"/*/; do
  nombre="$(basename "$skill")"
  ln -sfn "../../.agents/skills/$nombre" "$destino/$nombre"
done

echo "$(ls -1 "$destino" | wc -l) skills enlazadas en .claude/skills/"
