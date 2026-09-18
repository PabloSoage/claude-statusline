#!/usr/bin/env bash
# Status line: modelo y effort | contexto | cuota 5h | cuota semanal (con reinicios)
# Version Windows/Git Bash (usa GNU date/stat y lee el token del fichero de credenciales,
# no del Llavero de macOS).
input=$(cat)

# jq puede no estar en el PATH cuando Claude Code lanza este script (Git Bash no siempre
# hereda ~/.bashrc en modo no interactivo). Buscamos un jq usable en varias rutas.
JQ=jq
if ! command -v jq >/dev/null 2>&1; then
  for c in "$HOME/.local/bin/jq.exe" "$HOME/.local/bin/jq" "/mingw64/bin/jq.exe"; do
    [[ -x "$c" ]] && { JQ="$c"; break; }
  done
fi

# jq.exe en Windows escribe CRLF; quitamos el \r con tr en cada llamada para que los
# campos numericos no lleguen con basura al final (rompe comparaciones aritmeticas).
IFS=$'\x1f' read -r MODEL EFFORT CTX H5 H5_RESET WK WK_RESET < <(
  echo "$input" | "$JQ" -r '[
    (.model.display_name // "?"),
    (.effort.level // ""),
    (.context_window.used_percentage // "" | tostring),
    (.rate_limits.five_hour.used_percentage // "" | tostring),
    (.rate_limits.five_hour.resets_at // "" | tostring),
    (.rate_limits.seven_day.used_percentage // "" | tostring),
    (.rate_limits.seven_day.resets_at // "" | tostring)
  ] | join("")' | tr -d '\r'
)

RST=$'\033[0m'; DIM=$'\033[2m'
color() { # verde <50, amarillo <80, rojo >=80
  local p=${1%.*}
  if   (( p >= 80 )); then printf '\033[31m'
  elif (( p >= 50 )); then printf '\033[33m'
  else printf '\033[32m'; fi
}
bar() {
  local p=${1%.*} filled i out=""
  filled=$(( p / 10 )); (( filled > 10 )) && filled=10
  for ((i=0; i<10; i++)); do (( i < filled )) && out+="▓" || out+="░"; done
  printf '%s' "$out"
}
remaining() { # segundos hasta el epoch -> "2h05m" o "3d4h"
  local s=$(( $1 - $(date +%s) ))
  (( s < 0 )) && s=0
  if (( s >= 86400 )); then printf '%dd%dh' $((s/86400)) $((s%86400/3600))
  else printf '%dh%02dm' $((s/3600)) $((s%3600/60)); fi
}

# Endpoint de uso (el de /usage) con cache de 5 min refrescada en segundo plano
# Da la cuota de Fable, que no viene en el JSON, y 5h y semanal antes de la primera respuesta
# CLAUDE_CONFIG_DIR (p.ej. un alias con otra cuenta, como claude2) apunta a
# credenciales y cache propios; si no esta definida se usa ~/.claude.
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
USAGE_CACHE="$CONFIG_DIR/cache/usage.json"
CRED_FILE="$CONFIG_DIR/.credentials.json"
mtime=$(stat -c %Y "$USAGE_CACHE" 2>/dev/null || echo 0)
if (( $(date +%s) - mtime > 300 )); then
  mkdir -p "${USAGE_CACHE%/*}" && touch "$USAGE_CACHE"
  (
    token=$("$JQ" -r '.claudeAiOauth.accessToken // empty' "$CRED_FILE" 2>/dev/null | tr -d '\r')
    [[ -n $token ]] && curl -sf --max-time 10 https://api.anthropic.com/api/oauth/usage \
      -H "Authorization: Bearer $token" -H "anthropic-beta: oauth-2025-04-20" \
      -o "$USAGE_CACHE.tmp" && mv "$USAGE_CACHE.tmp" "$USAGE_CACHE"
  ) >/dev/null 2>&1 &
fi

# Sin respuesta de la API aun no hay rate_limits ni used_percentage
[[ -z $CTX ]] && CTX=0
from_cache() { # ventana del endpoint de uso -> "porcentaje<US>epoch de reinicio"
  "$JQ" -r --arg w "$1" '.[$w] | [(.utilization // "" | tostring),
    (.resets_at // "" | sub("\\..*"; "Z") | fromdateiso8601? // "" | tostring)] | join("")' \
    "$USAGE_CACHE" 2>/dev/null | tr -d '\r'
}
[[ -z $H5 ]] && IFS=$'\x1f' read -r H5 H5_RESET < <(from_cache five_hour)
[[ -z $WK ]] && IFS=$'\x1f' read -r WK WK_RESET < <(from_cache seven_day)
# Una ventana de la cache cuyo reinicio ya paso esta caducada
now=$(date +%s)
[[ -n $H5_RESET && $H5_RESET -lt $now ]] && H5=""
[[ -n $WK_RESET && $WK_RESET -lt $now ]] && WK=""

dia() { local d=(dom lun mar mié jue vie sáb); echo "${d[$(date -d @"$1" +%w)]}"; }

out="${DIM}${MODEL}${RST}"
[[ -n $EFFORT ]] && out+=" ${DIM}·${RST} ${EFFORT}"

if [[ -n $CTX ]]; then
  c=$(color "$CTX")
  out+=" │ ctx ${c}$(bar "$CTX") ${CTX%.*}%${RST}"
fi

if [[ -n $H5 ]]; then
  c=$(color "$H5")
  out+=" │ 5h ${c}${H5%.*}%${RST}"
  [[ -n $H5_RESET ]] && out+=" ${DIM}↻ $(date -d @"$H5_RESET" +%H:%M) ($(remaining "$H5_RESET"))${RST}"
fi

if [[ -n $WK ]]; then
  c=$(color "$WK")
  out+=" │ wk ${c}${WK%.*}%${RST}"
  [[ -n $WK_RESET ]] && out+=" ${DIM}↻ $(dia "$WK_RESET") $(date -d @"$WK_RESET" '+%d %H:%M') ($(remaining "$WK_RESET"))${RST}"
fi

IFS=$'\x1f' read -r FB FB_RESET < <(
  "$JQ" -r 'first(.limits[]? | select(.kind == "weekly_scoped" and .scope.model.display_name == "Fable"))
    | [(.percent | tostring), (.resets_at // "" | sub("\\..*"; "Z") | fromdateiso8601? // "" | tostring)] | join("")' \
    "$USAGE_CACHE" 2>/dev/null | tr -d '\r'
)

if [[ -n $FB ]]; then
  c=$(color "$FB")
  out+=" │ fable ${c}${FB%.*}%${RST}"
  [[ -n $FB_RESET ]] && out+=" ${DIM}↻ $(dia "$FB_RESET") $(date -d @"$FB_RESET" '+%d %H:%M')${RST}"
fi

printf '%s\n' "$out"
