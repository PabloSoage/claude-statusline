#!/usr/bin/env bash
# Instala la status line en ~/.claude y la registra en ~/.claude/settings.json
set -euo pipefail
cd "$(dirname "$0")"

JQ=jq
if ! command -v jq >/dev/null 2>&1; then
  for c in "$HOME/.local/bin/jq.exe" "$HOME/.local/bin/jq" "/mingw64/bin/jq.exe"; do
    [[ -x "$c" ]] && { JQ="$c"; break; }
  done
fi
command -v "$JQ" >/dev/null || { echo "Falta jq. En macOS: brew install jq. En Windows: descarga jq-windows-amd64.exe de https://github.com/jqlang/jq/releases y colocalo en ~/.local/bin/jq.exe"; exit 1; }

mkdir -p ~/.claude
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh

settings=~/.claude/settings.json
[[ -f $settings ]] || echo '{}' > "$settings"
cp "$settings" "$settings.bak"
"$JQ" '.statusLine = {type: "command", command: "~/.claude/statusline.sh", padding: 0, refreshInterval: 60}' \
  "$settings.bak" > "$settings"

echo "Instalado. Copia de seguridad de settings en $settings.bak"
echo "Prueba:"
echo '{"model":{"display_name":"Test"},"context_window":{"used_percentage":25}}' | ~/.claude/statusline.sh
