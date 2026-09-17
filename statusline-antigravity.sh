#!/usr/bin/env bash
# Status line for Google Antigravity CLI (agy)
# Displays: model and reasoning effort | context window | 5h quota | weekly quota for selected model
# Compatible with macOS, Linux, and Windows (Git Bash).

input=$(cat)

# 1. Locate jq and agy
JQ=jq
if ! command -v jq >/dev/null 2>&1; then
  for c in "$HOME/.local/bin/jq.exe" "$HOME/.local/bin/jq" "/mingw64/bin/jq.exe" "/usr/bin/jq" "/usr/local/bin/jq" "/opt/homebrew/bin/jq"; do
    [[ -x "$c" ]] && { JQ="$c"; break; }
  done
fi

if ! command -v agy >/dev/null 2>&1; then
  for a in "$LOCALAPPDATA/agy/bin/agy.exe" "$HOME/AppData/Local/agy/bin/agy.exe" "/c/Users/$USER/AppData/Local/agy/bin/agy.exe"; do
    [[ -x "$a" ]] && { export PATH="${a%/*}:$PATH"; break; }
  done
fi

# 2. Extract model name, model id, effort, and context window
IFS=$'\x1f' read -r MODEL_NAME MODEL_ID EFFORT CTX_RAW < <(
  echo "$input" | "$JQ" -r '[
    (.model.display_name // .model.id // "?"),
    (.model.id // ""),
    (.model.effort // .effort.level // .effort // ""),
    (.context_window.used_percentage // (
      if (.context_window.total_input_tokens and .context_window.context_window_size and .context_window.context_window_size > 0)
      then ((.context_window.total_input_tokens / .context_window.context_window_size) * 100)
      else "" end
    ) // "" | tostring)
  ] | join("\u001f")' | tr -d '\r'
)

# Normalize context window percentage (0..100)
CTX=""
if [[ -n $CTX_RAW && $CTX_RAW != "null" ]]; then
  CTX=$(awk -v v="$CTX_RAW" 'BEGIN { if (v > 0 && v <= 1) printf "%.0f", v*100; else printf "%.0f", v }')
fi

# 3. Determine quota group for the currently selected model
# Antigravity separates quotas into "Gemini Models" and "Claude and GPT models"
MODEL_LOWER=$(echo "$MODEL_ID $MODEL_NAME" | tr '[:upper:]' '[:lower:]')
if [[ $MODEL_LOWER =~ (claude|sonnet|opus|haiku|gpt|3p) ]]; then
  GROUP_KEY="3p"
  GROUP_NAME="Claude and GPT models"
else
  GROUP_KEY="gemini"
  GROUP_NAME="Gemini Models"
fi

# 4. Helpers: color coding, progress bar, remaining time, date parsing
RST=$'\033[0m'; DIM=$'\033[2m'
color() { # green <50, yellow <80, red >=80
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

remaining() { # seconds to epoch -> "2h05m" or "3d4h"
  local now; now=$(date +%s)
  local s=$(( $1 - now ))
  (( s < 0 )) && s=0
  if (( s >= 86400 )); then
    printf '%dd%dh' $((s/86400)) $((s%86400/3600))
  else
    printf '%dh%02dm' $((s/3600)) $((s%3600/60))
  fi
}

parse_epoch() {
  local t="$1"
  [[ -z $t || $t == "null" ]] && return
  if [[ $t =~ ^[0-9]+$ ]]; then
    echo "$t"
  elif date -d "$t" +%s >/dev/null 2>&1; then
    # GNU date (Linux, Windows Git Bash)
    date -d "$t" +%s
  else
    # macOS BSD date
    local clean_t="${t%%.*}Z"
    date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$clean_t" +%s 2>/dev/null || echo ""
  fi
}

fmt_time() { # epoch -> HH:MM
  local ep="$1"
  date -d @"$ep" +%H:%M 2>/dev/null || date -r "$ep" +%H:%M 2>/dev/null || echo ""
}

fmt_day_time() { # epoch -> dd HH:MM
  local ep="$1"
  date -d @"$ep" '+%d %H:%M' 2>/dev/null || date -r "$ep" '+%d %H:%M' 2>/dev/null || echo ""
}

day_name() {
  local ep="$1"
  local d=(Sun Mon Tue Wed Thu Fri Sat)
  local w
  w=$(date -d @"$ep" +%w 2>/dev/null || date -r "$ep" +%w 2>/dev/null || echo 0)
  echo "${d[$w]}"
}

# 5. Extract quota from stdin input (.quota) if available
H5_USED=""
H5_RESET=""
WK_USED=""
WK_RESET=""

IFS=$'\x1f' read -r H5_USED H5_RESET WK_USED WK_RESET < <(
  echo "$input" | "$JQ" -r --arg prefix "$GROUP_KEY" '
    .quota as $q |
    if $q and ($q | type == "object") and ($q | length > 0) then
      ($q[($prefix + "-5h")] // ($q | to_entries[] | select(.key | contains($prefix) and contains("5h")) | .value)) as $b5 |
      ($q[($prefix + "-weekly")] // ($q | to_entries[] | select(.key | contains($prefix) and contains("weekly")) | .value)) as $bw |
      [
        (if $b5.remaining_fraction != null then ((1.0 - $b5.remaining_fraction) * 100 | round | tostring)
         elif $b5.used_percentage != null then ($b5.used_percentage | round | tostring)
         else "" end),
        ($b5.reset_time // ($b5.reset_in_seconds | tostring) // ""),
        (if $bw.remaining_fraction != null then ((1.0 - $bw.remaining_fraction) * 100 | round | tostring)
         elif $bw.used_percentage != null then ($bw.used_percentage | round | tostring)
         else "" end),
        ($bw.reset_time // ($bw.reset_in_seconds | tostring) // "")
      ] | join("\u001f")
    else
      ""
    end
  ' 2>/dev/null | tr -d '\r'
)

# 6. Usage cache fallback (~/.gemini/antigravity-cli/cache/usage.json)
CACHE_DIR="$HOME/.gemini/antigravity-cli/cache"
USAGE_CACHE="$CACHE_DIR/usage.json"
NOW=$(date +%s)

mtime=0
if [[ -f $USAGE_CACHE ]]; then
  mtime=$(stat -c %Y "$USAGE_CACHE" 2>/dev/null || stat -f %m "$USAGE_CACHE" 2>/dev/null || echo 0)
fi

# Refresh cache in background if older than 5 minutes (300 seconds)
if (( NOW - mtime > 300 )); then
  mkdir -p "$CACHE_DIR" 2>/dev/null
  touch "$USAGE_CACHE" 2>/dev/null
  (
    # MSYS_NO_PATHCONV=1 prevents Git Bash from converting /usage to a file path
    MSYS_NO_PATHCONV=1 agy -p "/usage" --output-format json > "$USAGE_CACHE.tmp" 2>/dev/null && mv "$USAGE_CACHE.tmp" "$USAGE_CACHE"
  ) >/dev/null 2>&1 &
fi

# If quota missing in stdin, read from cache
if [[ -z $H5_USED || -z $WK_USED ]] && [[ -f $USAGE_CACHE ]]; then
  IFS=$'\x1f' read -r CH5_USED CH5_RESET CWK_USED CWK_RESET < <(
    "$JQ" -r --arg gname "$GROUP_NAME" --arg prefix "$GROUP_KEY" '
      .command.data.groups as $groups |
      if $groups then
        ($groups[] | select(.name == $gname or (.name | contains($gname)))) as $g |
        ($g.buckets[] | select(.window == "5h" or (.id | endswith("-5h")))) as $b5 |
        ($g.buckets[] | select(.window == "weekly" or (.id | endswith("-weekly")))) as $bw |
        [
          (if $b5.remaining_fraction != null then ((1.0 - $b5.remaining_fraction) * 100 | round | tostring) else "" end),
          ($b5.reset_time // ""),
          (if $bw.remaining_fraction != null then ((1.0 - $bw.remaining_fraction) * 100 | round | tostring) else "" end),
          ($bw.reset_time // "")
        ] | join("\u001f")
      else
        ""
      end
    ' "$USAGE_CACHE" 2>/dev/null | tr -d '\r'
  )
  [[ -z $H5_USED ]] && H5_USED="$CH5_USED" && H5_RESET="$CH5_RESET"
  [[ -z $WK_USED ]] && WK_USED="$CWK_USED" && WK_RESET="$CWK_RESET"
fi

H5_EPOCH=$(parse_epoch "$H5_RESET")
WK_EPOCH=$(parse_epoch "$WK_RESET")

# Discard if reset time is already in the past
if [[ -n $H5_EPOCH && $H5_EPOCH -lt $NOW ]]; then
  H5_USED=""
  H5_EPOCH=""
fi
if [[ -n $WK_EPOCH && $WK_EPOCH -lt $NOW ]]; then
  WK_USED=""
  WK_EPOCH=""
fi

# 7. Assemble output string
out="${DIM}${MODEL_NAME}${RST}"
if [[ -n $EFFORT && $EFFORT != "null" ]]; then
  EFFORT_LOWER=$(echo "$EFFORT" | tr '[:upper:]' '[:lower:]')
  MODEL_NAME_LOWER=$(echo "$MODEL_NAME" | tr '[:upper:]' '[:lower:]')
  # Prevent duplicating "(Medium) · medium" if already part of the model name
  if [[ ! $MODEL_NAME_LOWER =~ \($EFFORT_LOWER\) ]]; then
    out+=" ${DIM}·${RST} ${EFFORT}"
  fi
fi

# Context window usage
if [[ -n $CTX && $CTX != "null" ]]; then
  c=$(color "$CTX")
  out+=" │ ctx ${c}$(bar "$CTX") ${CTX}%${RST}"
fi

# 5-hour quota
if [[ -n $H5_USED && $H5_USED != "null" ]]; then
  c=$(color "$H5_USED")
  out+=" │ 5h ${c}${H5_USED%.*}%${RST}"
  if [[ -n $H5_EPOCH ]]; then
    h5_time=$(fmt_time "$H5_EPOCH")
    rem=$(remaining "$H5_EPOCH")
    [[ -n $h5_time ]] && out+=" ${DIM}↻ ${h5_time} (${rem})${RST}"
  fi
fi

# Weekly quota
if [[ -n $WK_USED && $WK_USED != "null" ]]; then
  c=$(color "$WK_USED")
  out+=" │ sem ${c}${WK_USED}%${RST}"
  if [[ -n $WK_EPOCH ]]; then
    d_name=$(day_name "$WK_EPOCH")
    wk_time=$(fmt_day_time "$WK_EPOCH")
    rem=$(remaining "$WK_EPOCH")
    [[ -n $wk_time ]] && out+=" ${DIM}↻ ${d_name} ${wk_time} (${rem})${RST}"
  fi
fi

printf '%s\n' "$out"
