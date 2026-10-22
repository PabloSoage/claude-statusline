#!/usr/bin/env bash
# Status line for Google Antigravity CLI (agy)
# Displays: model and reasoning effort | context window | 5h quota | weekly quota for selected model
# Compatible with macOS, Linux, and Windows (Git Bash).

input=$(cat)

# 1. Locate jq
JQ=jq
if ! command -v jq >/dev/null 2>&1; then
  for c in "$HOME/.local/bin/jq.exe" "$HOME/.local/bin/jq" "/mingw64/bin/jq.exe" "/usr/bin/jq" "/usr/local/bin/jq" "/opt/homebrew/bin/jq"; do
    [[ -x "$c" ]] && { JQ="$c"; break; }
  done
fi

# 2. Extract model, effort, context, and quota in a single jq call (avoids process spawns and FIFO deadlocks)
PARSED=$(echo "$input" | "$JQ" -r '
  . as $root |
  ((.model.id // "") + " " + (.model.display_name // "")) | ascii_downcase as $m |
  (if ($m | test("claude|sonnet|opus|haiku|gpt|3p")) then "3p" else "gemini" end) as $gkey |
  (if $gkey == "3p" then "Claude and GPT models" else "Gemini Models" end) as $gname |
  $root.quota as $q |
  (if $q and ($q | type == "object") and ($q | length > 0) then
    ($q[($gkey + "-5h")] // ($q | to_entries[] | select(.key | contains($gkey) and contains("5h")) | .value))
  else null end) as $b5 |
  (if $q and ($q | type == "object") and ($q | length > 0) then
    ($q[($gkey + "-weekly")] // ($q | to_entries[] | select(.key | contains($gkey) and contains("weekly")) | .value))
  else null end) as $bw |
  [
    ($root.model.display_name // $root.model.id // "?"),
    ($root.model.id // ""),
    ($root.model.effort // $root.effort.level // $root.effort // ""),
    (if $root.context_window.used_percentage != null then ($root.context_window.used_percentage | round | tostring)
     elif ($root.context_window.total_input_tokens and $root.context_window.context_window_size and $root.context_window.context_window_size > 0)
     then ((($root.context_window.total_input_tokens / $root.context_window.context_window_size) * 100) | round | tostring)
     else "" end),
    $gkey,
    $gname,
    (if $b5 != null and $b5.remaining_fraction != null then ((1.0 - $b5.remaining_fraction) * 100 | round | tostring)
     elif $b5 != null and $b5.used_percentage != null then ($b5.used_percentage | round | tostring)
     else "" end),
    (if $b5 != null and $b5.reset_time != null then $b5.reset_time
     elif $b5 != null and $b5.reset_in_seconds != null then ($b5.reset_in_seconds | tostring)
     else "" end),
    (if $bw != null and $bw.remaining_fraction != null then ((1.0 - $bw.remaining_fraction) * 100 | round | tostring)
     elif $bw != null and $bw.used_percentage != null then ($bw.used_percentage | round | tostring)
     else "" end),
    (if $bw != null and $bw.reset_time != null then $bw.reset_time
     elif $bw != null and $bw.reset_in_seconds != null then ($bw.reset_in_seconds | tostring)
     else "" end)
  ] | join("\u001f")
' 2>/dev/null | tr -d '\r')

IFS=$'\x1f' read -r MODEL_NAME MODEL_ID EFFORT CTX GROUP_KEY GROUP_NAME H5_USED H5_RESET WK_USED WK_RESET <<< "$PARSED"

# 3. Usage cache fallback (~/.gemini/antigravity-cli/cache/usage.json)
CACHE_DIR="$HOME/.gemini/antigravity-cli/cache"
USAGE_CACHE="$CACHE_DIR/usage.json"
NOW=$(date +%s)

# Save fresh quota from stdin to local cache when available
if [[ -n $H5_RESET && $H5_RESET != "null" ]]; then
  mkdir -p "$CACHE_DIR" 2>/dev/null
  echo "$input" | "$JQ" '{quota: .quota}' > "$USAGE_CACHE.tmp" 2>/dev/null && mv "$USAGE_CACHE.tmp" "$USAGE_CACHE" 2>/dev/null
fi

# In new chats, Antigravity sends uninitialized quota (no reset_time). Fall back to local cache.
if [[ -z $H5_RESET || $H5_RESET == "null" || -z $H5_USED || -z $WK_RESET || $WK_RESET == "null" || -z $WK_USED ]] && [[ -f $USAGE_CACHE ]]; then
  CACHED_PARSED=$("$JQ" -r --arg gname "$GROUP_NAME" --arg prefix "$GROUP_KEY" '
    if .quota then
      (.quota[($prefix + "-5h")] // (.quota | to_entries[] | select(.key | contains($prefix) and contains("5h")) | .value)) as $b5 |
      (.quota[($prefix + "-weekly")] // (.quota | to_entries[] | select(.key | contains($prefix) and contains("weekly")) | .value)) as $bw |
      [
        (if $b5.remaining_fraction != null then ((1.0 - $b5.remaining_fraction) * 100 | round | tostring)
         elif $b5.used_percentage != null then ($b5.used_percentage | round | tostring)
         else "" end),
        (if $b5.reset_time != null then $b5.reset_time elif $b5.reset_in_seconds != null then ($b5.reset_in_seconds | tostring) else "" end),
        (if $bw.remaining_fraction != null then ((1.0 - $bw.remaining_fraction) * 100 | round | tostring)
         elif $bw.used_percentage != null then ($bw.used_percentage | round | tostring)
         else "" end),
        (if $bw.reset_time != null then $bw.reset_time elif $bw.reset_in_seconds != null then ($bw.reset_in_seconds | tostring) else "" end)
      ] | join("\u001f")
    elif .command.data.groups then
      (.command.data.groups[] | select(.name == $gname or (.name | contains($gname)))) as $g |
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

  IFS=$'\x1f' read -r CH5_USED CH5_RESET CWK_USED CWK_RESET <<< "$CACHED_PARSED"

  if [[ -z $H5_RESET || $H5_RESET == "null" || -z $H5_USED ]]; then
    if [[ -n $CH5_RESET && $CH5_RESET != "null" ]]; then
      H5_USED="$CH5_USED"
      H5_RESET="$CH5_RESET"
    else
      H5_USED=""
      H5_RESET=""
    fi
  fi
  if [[ -z $WK_RESET || $WK_RESET == "null" || -z $WK_USED ]]; then
    if [[ -n $CWK_RESET && $CWK_RESET != "null" ]]; then
      WK_USED="$CWK_USED"
      WK_RESET="$CWK_RESET"
    else
      WK_USED=""
      WK_RESET=""
    fi
  fi
fi

# If reset time is still absent, do not display uninitialized zero values
[[ -z $H5_RESET || $H5_RESET == "null" ]] && H5_USED=""
[[ -z $WK_RESET || $WK_RESET == "null" ]] && WK_USED=""

# Helper functions: epoch and duration parsing
parse_epoch() {
  local t="$1"
  [[ -z $t || $t == "null" ]] && return
  if [[ $t =~ ^[0-9]+$ ]]; then
    echo "$t"
  else
    date -d "$t" +%s 2>/dev/null || date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "${t%%.*}Z" +%s 2>/dev/null || echo ""
  fi
}

H5_EPOCH=$(parse_epoch "$H5_RESET")
WK_EPOCH=$(parse_epoch "$WK_RESET")

# Discard if reset time is already in the past
if [[ -n $H5_EPOCH && $H5_EPOCH -lt $NOW ]]; then
  H5_USED=""
  H5_RESET=""
  H5_EPOCH=""
fi
if [[ -n $WK_EPOCH && $WK_EPOCH -lt $NOW ]]; then
  WK_USED=""
  WK_RESET=""
  WK_EPOCH=""
fi

# 4. Formatting and colors
RST=$'\033[0m'; DIM=$'\033[2m'
color() {
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

remaining() {
  local s=$(( $1 - NOW ))
  (( s < 0 )) && s=0
  if (( s >= 86400 )); then
    printf '%dd%dh' $((s/86400)) $((s%86400/3600))
  else
    printf '%dh%02dm' $((s/3600)) $((s%3600/60))
  fi
}

out="${DIM}${MODEL_NAME}${RST}"
if [[ -n $EFFORT && $EFFORT != "null" ]]; then
  EFFORT_LOWER=$(echo "$EFFORT" | tr '[:upper:]' '[:lower:]')
  MODEL_NAME_LOWER=$(echo "$MODEL_NAME" | tr '[:upper:]' '[:lower:]')
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
if [[ -n $H5_USED && $H5_USED != "null" && -n $H5_EPOCH ]]; then
  c=$(color "$H5_USED")
  out+=" │ 5h ${c}${H5_USED}%${RST}"
  h5_time=$(date -d @"$H5_EPOCH" +%H:%M 2>/dev/null || date -r "$H5_EPOCH" +%H:%M 2>/dev/null)
  rem=$(remaining "$H5_EPOCH")
  [[ -n $h5_time ]] && out+=" ${DIM}↻ ${h5_time} (${rem})${RST}"
fi

# Weekly quota
if [[ -n $WK_USED && $WK_USED != "null" && -n $WK_EPOCH ]]; then
  c=$(color "$WK_USED")
  out+=" │ wk ${c}${WK_USED}%${RST}"
  wk_raw=$(date -d @"$WK_EPOCH" '+%w %d %H:%M' 2>/dev/null || date -r "$WK_EPOCH" '+%w %d %H:%M' 2>/dev/null)
  if [[ -n $wk_raw ]]; then
    d_list=(Sun Mon Tue Wed Thu Fri Sat)
    w_idx=${wk_raw%% *}
    wk_time=${wk_raw#* }
    d_name=${d_list[$w_idx]}
    rem=$(remaining "$WK_EPOCH")
    out+=" ${DIM}↻ ${d_name} ${wk_time} (${rem})${RST}"
  fi
fi

printf '%s\n' "$out"
exit 0
