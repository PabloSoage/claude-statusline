#!/usr/bin/env bash
# Installs status line for Google Antigravity CLI (agy)
# Configures ~/.gemini/antigravity-cli/settings.json
set -euo pipefail
cd "$(dirname "$0")"

JQ=jq
if ! command -v jq >/dev/null 2>&1; then
  for c in "$HOME/.local/bin/jq.exe" "$HOME/.local/bin/jq" "/mingw64/bin/jq.exe" "/usr/bin/jq" "/usr/local/bin/jq" "/opt/homebrew/bin/jq"; do
    [[ -x "$c" ]] && { JQ="$c"; break; }
  done
fi

command -v "$JQ" >/dev/null 2>&1 || {
  echo "Error: jq is required."
  echo "  - macOS: brew install jq"
  echo "  - Linux: sudo apt install jq"
  echo "  - Windows: download jq-windows-amd64.exe from https://github.com/jqlang/jq/releases and place it at ~/.local/bin/jq.exe"
  exit 1
}

INSTALL_DIR="$HOME/.antigravity-statusline"
mkdir -p "$INSTALL_DIR"
cp statusline-antigravity.sh "$INSTALL_DIR/statusline.sh"
chmod +x "$INSTALL_DIR/statusline.sh"

SETTINGS_DIR="$HOME/.gemini/antigravity-cli"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
mkdir -p "$SETTINGS_DIR"
[[ -f "$SETTINGS_FILE" ]] || echo '{}' > "$SETTINGS_FILE"
cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak"

SCRIPT_PATH="$INSTALL_DIR/statusline.sh"

# On Windows Git Bash, provide bash command invocation with POSIX path
UNAME=$(uname -s 2>/dev/null || echo "Unknown")
if [[ $UNAME =~ (MINGW|MSYS|CYGWIN|Windows) ]]; then
  SCRIPT_CMD="bash $SCRIPT_PATH"
else
  SCRIPT_CMD="bash $SCRIPT_PATH"
fi

"$JQ" --arg cmd "$SCRIPT_CMD" '
  .statusLine = {
    command: $cmd,
    enabled: true
  }
' "$SETTINGS_FILE.bak" > "$SETTINGS_FILE"

echo "Installed successfully to $INSTALL_DIR/statusline.sh"
echo "Updated $SETTINGS_FILE (backup saved to settings.json.bak)"
echo ""
echo "Test (Gemini model):"
echo '{"model":{"id":"gemini-3.8-flash-medium","display_name":"Gemini 3.8 Flash (Medium)","effort":"medium"},"context_window":{"used_percentage":25}}' | "$INSTALL_DIR/statusline.sh"
echo ""
echo "Test (Claude model):"
echo '{"model":{"id":"claude-sonnet-4-6","display_name":"Claude Sonnet 4.6 (Thinking)","effort":"high"},"context_window":{"used_percentage":40}}' | "$INSTALL_DIR/statusline.sh"
