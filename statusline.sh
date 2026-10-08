#!/usr/bin/env bash
# Status line: modelo y effort | contexto | cuota 5h | cuota semanal (con reinicios)
# Funciona en macOS (date -r, stat -f y el token del Llavero) y en Windows/Git Bash o Linux
# (GNU date/stat y el token de .credentials.json); se detecta al arrancar.
input=$(cat)

# jq puede no estar en el PATH cuando Claude Code lanza este script (Git Bash no siempre
# hereda ~/.bashrc en modo no interactivo; en macOS, el de Homebrew puede faltar del PATH).
# Buscamos un jq usable en varias rutas.
JQ=jq
if ! command -v jq >/dev/null 2>&1; then
  for c in "$HOME/.local/bin/jq.exe" "$HOME/.local/bin/jq" "/mingw64/bin/jq.exe" \
            "/opt/homebrew/bin/jq" "/usr/local/bin/jq"; do
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
  ] | join("\u001f")' | tr -d '\r'
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
# GNU date/stat (Windows/Git Bash, Linux) o BSD (macOS)
if date -d @0 +%s >/dev/null 2>&1; then
  fmt_epoch() { date -d @"$1" "+$2"; }
  file_mtime() { stat -c %Y "$1" 2>/dev/null; }
else
  fmt_epoch() { date -r "$1" "+$2"; }
  file_mtime() { stat -f %m "$1" 2>/dev/null; }
fi
fmt_dur() { # segundos -> "4m32s" o "45s"
  local s=$1; (( s < 0 )) && s=0
  if (( s >= 60 )); then printf '%dm%02ds' $((s/60)) $((s%60))
  else printf '%ds' "$s"; fi
}

# Endpoint de uso (el de /usage) con cache de 5 min refrescada en segundo plano
# Da la cuota de Fable, que no viene en el JSON, y 5h y semanal antes de la primera respuesta
# CLAUDE_CONFIG_DIR (p.ej. un alias con otra cuenta, como claude2) apunta a
# credenciales y cache propios; si no esta definida se usa ~/.claude.
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
USAGE_CACHE="$CONFIG_DIR/cache/usage.json"
CRED_FILE="$CONFIG_DIR/.credentials.json"
mtime=$(file_mtime "$USAGE_CACHE" || echo 0)
if (( $(date +%s) - mtime > 300 )); then
  mkdir -p "${USAGE_CACHE%/*}" && touch "$USAGE_CACHE"
  (
    if [[ -f $CRED_FILE ]]; then
      token=$("$JQ" -r '.claudeAiOauth.accessToken // empty' "$CRED_FILE" 2>/dev/null | tr -d '\r')
    elif command -v security >/dev/null 2>&1; then  # macOS: el token esta en el Llavero
      token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null |
        "$JQ" -r '.claudeAiOauth.accessToken // empty')
    fi
    [[ -n $token ]] && curl -sf --max-time 10 https://api.anthropic.com/api/oauth/usage \
      -H "Authorization: Bearer $token" -H "anthropic-beta: oauth-2025-04-20" \
      -o "$USAGE_CACHE.tmp" && mv "$USAGE_CACHE.tmp" "$USAGE_CACHE"
  ) >/dev/null 2>&1 &
fi

# Sin respuesta de la API aun no hay rate_limits ni used_percentage
[[ -z $CTX ]] && CTX=0
from_cache() { # ventana del endpoint de uso -> "porcentaje<US>epoch de reinicio"
  "$JQ" -r --arg w "$1" '.[$w] | [(.utilization // "" | tostring),
    (.resets_at // "" | sub("\\..*"; "Z") | fromdateiso8601? // "" | tostring)] | join("\u001f")' \
    "$USAGE_CACHE" 2>/dev/null | tr -d '\r'
}
[[ -z $H5 ]] && IFS=$'\x1f' read -r H5 H5_RESET < <(from_cache five_hour)
[[ -z $WK ]] && IFS=$'\x1f' read -r WK WK_RESET < <(from_cache seven_day)
# Una ventana de la cache cuyo reinicio ya paso esta caducada
now=$(date +%s)
[[ -n $H5_RESET && $H5_RESET -lt $now ]] && H5=""
[[ -n $WK_RESET && $WK_RESET -lt $now ]] && WK=""

dia() { local d=(dom lun mar mié jue vie sáb); echo "${d[$(fmt_epoch "$1" %w)]}"; }

out="${DIM}${MODEL}${RST}"
[[ -n $EFFORT ]] && out+=" ${DIM}·${RST} ${EFFORT}"

if [[ -n $CTX ]]; then
  c=$(color "$CTX")
  out+=" │ ctx ${c}$(bar "$CTX") ${CTX%.*}%${RST}"
fi

if [[ -n $H5 ]]; then
  c=$(color "$H5")
  out+=" │ 5h ${c}${H5%.*}%${RST}"
  [[ -n $H5_RESET ]] && out+=" ${DIM}↻ $(fmt_epoch "$H5_RESET" %H:%M) ($(remaining "$H5_RESET"))${RST}"
fi

if [[ -n $WK ]]; then
  c=$(color "$WK")
  out+=" │ wk ${c}${WK%.*}%${RST}"
  [[ -n $WK_RESET ]] && out+=" ${DIM}↻ $(dia "$WK_RESET") $(fmt_epoch "$WK_RESET" '%d %H:%M') ($(remaining "$WK_RESET"))${RST}"
fi

IFS=$'\x1f' read -r FB FB_RESET < <(
  "$JQ" -r 'first(.limits[]? | select(.kind == "weekly_scoped" and .scope.model.display_name == "Fable"))
    | [(.percent | tostring), (.resets_at // "" | sub("\\..*"; "Z") | fromdateiso8601? // "" | tostring)] | join("\u001f")' \
    "$USAGE_CACHE" 2>/dev/null | tr -d '\r'
)

if [[ -n $FB ]]; then
  c=$(color "$FB")
  out+=" │ fable ${c}${FB%.*}%${RST}"
  [[ -n $FB_RESET ]] && out+=" ${DIM}↻ $(dia "$FB_RESET") $(fmt_epoch "$FB_RESET" '%d %H:%M')${RST}"
fi

# TTL restante de la prompt cache de Anthropic (no la de usage.json: esa es la del
# endpoint /usage). Claude Code cachea el prompt con TTL de 1h por defecto, y baja a
# 5m si la cuenta entra en overage. No viene en el JSON de stdin, así que se calcula
# a partir del ultimo evento de cache (lectura o escritura) del transcript de la sesion:
# el tipo de TTL se toma del ultimo cache_creation con ese TTL, y la cuenta atras sale
# de sumarle el TTL al timestamp de ese ultimo evento.
TRANSCRIPT=$(echo "$input" | "$JQ" -r '.transcript_path // empty' | tr -d '\r')
if [[ -n $TRANSCRIPT && -f $TRANSCRIPT ]]; then
  IFS=$'\x1f' read -r CACHE_EPOCH CACHE_TTL < <(
    tail -n 500 "$TRANSCRIPT" | "$JQ" -rs '
      [.[] | select(.type == "assistant" and .message.usage != null)] as $all |
      ([$all[] | select((.message.usage.cache_read_input_tokens // 0) > 0
        or (.message.usage.cache_creation_input_tokens // 0) > 0)] | .[-1]) as $touch |
      ([$all[] | select((.message.usage.cache_creation.ephemeral_1h_input_tokens // 0) > 0)] | .[-1]) as $w1h |
      ([$all[] | select((.message.usage.cache_creation.ephemeral_5m_input_tokens // 0) > 0)] | .[-1]) as $w5m |
      if $touch == null then "" else
        [
          ($touch.timestamp // "" | sub("\\..*"; "Z") | fromdateiso8601? // "" | tostring),
          (if $w1h != null then "3600" elif $w5m != null then "300" else "3600" end)
        ] | join("\u001f")
      end
    ' 2>/dev/null | tr -d '\r'
  )
fi

if [[ -n $CACHE_EPOCH ]]; then
  left=$(( CACHE_EPOCH + CACHE_TTL - $(date +%s) ))
  if (( left > 0 )); then
    pct_left=$(( left * 100 / CACHE_TTL ))
    if   (( pct_left >= 75 )); then Q="●"
    elif (( pct_left >= 50 )); then Q="◕"
    elif (( pct_left >= 25 )); then Q="◑"
    else Q="◔"; fi
    c=$(color $(( 100 - pct_left )))
    ttl_label="5m"; (( CACHE_TTL == 3600 )) && ttl_label="1h"
    out+=" │ cache ${c}${Q}${RST} ${DIM}${ttl_label} ↻ $(fmt_dur "$left")${RST}"
  fi
fi

printf '%s\n' "$out"
