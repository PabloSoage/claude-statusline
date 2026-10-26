#!/usr/bin/env bash
# Status line for Google Antigravity CLI (agy)
# Displays: model and reasoning effort | context window | 5h quota | weekly quota for selected model
# Compatible with macOS, Linux, and Windows (Git Bash).

# Every external command is a fork, and forks cost ~25 ms each under Git Bash on Windows; agy
# repaints this line constantly and a slow command makes the prompt redraw over what you type
# (arrow keys in /resume stop working). So the script sticks to bash builtins and one jq call.
IFS= read -rd '' input || true

# 1. Locate jq
JQ=jq
if ! command -v jq >/dev/null 2>&1; then
  for c in "$HOME/.local/bin/jq.exe" "$HOME/.local/bin/jq" "/mingw64/bin/jq.exe" "/usr/bin/jq" "/usr/local/bin/jq" "/opt/homebrew/bin/jq"; do
    [[ -x "$c" ]] && { JQ="$c"; break; }
  done
fi
# A mise shim re-launches mise on every call to pick the version (~200 ms on Windows).
# Resolve the real binary once and cache it; if it disappears (after `mise up`), resolve again.
if [[ $(command -v "$JQ") == */mise/shims/* ]]; then
  jq_cache="$HOME/.cache/statusline-jq-path"
  real=$(<"$jq_cache") 2>/dev/null
  if [[ ! -x $real ]]; then
    real=$(mise which jq 2>/dev/null | tr -d '\r')
    command -v cygpath >/dev/null && [[ -n $real ]] && real=$(cygpath -u "$real")
    [[ -x $real ]] && mkdir -p "${jq_cache%/*}" && printf '%s' "$real" > "$jq_cache"
  fi
  [[ -x $real ]] && JQ=$real
fi

# 2. Model, effort, context and quota in a single jq call. In new chats Antigravity sends quota
#    without reset_time, so each bucket falls back to the last quota seen (usage cache).
#    Reset times come back as epochs, already dropped if they are in the past.
CACHE_DIR="$HOME/.gemini/antigravity-cli/cache"
USAGE_CACHE="$CACHE_DIR/usage.json"
cached=""
[[ -f $USAGE_CACHE ]] && cached=$(<"$USAGE_CACHE")

PARSED=$("$JQ" -r --arg cache "$cached" '
  def epoch:
    if . == null or . == "" then null
    elif type == "number" then floor
    elif test("^[0-9]+$") then tonumber
    else (sub("\\.[0-9]+"; "") | sub("[+]00:00$"; "Z") | try fromdateiso8601 catch null) end;
  def pct:
    if . == null then null
    elif .remaining_fraction != null then ((1 - .remaining_fraction) * 100 | round)
    elif .used_percentage != null then (.used_percentage | round)
    else null end;
  def reset:
    if . == null then null
    elif .reset_time != null then (.reset_time | epoch)
    elif .reset_in_seconds != null then (now + .reset_in_seconds | floor)
    else null end;
  def bucket($q; $k; $w):
    if ($q | type) == "object" and ($q | length) > 0
    then ($q[$k + "-" + $w] // first($q | to_entries[] | select(.key | contains($k) and contains($w)) | .value))
    else null end;
  def cached_bucket($c; $k; $w; $gname):
    if $c == null then null
    elif $c.quota then bucket($c.quota; $k; $w)
    elif $c.command.data.groups then
      first($c.command.data.groups[] | select(.name == $gname or (.name | contains($gname)))
        | .buckets[] | select(.window == $w or (.id | endswith("-" + $w))))
    else null end;
  def pick($r; $c; $k; $w; $gname):
    bucket($r.quota; $k; $w) as $b |
    (if ($b | reset) != null and ($b | pct) != null then $b else cached_bucket($c; $k; $w; $gname) end) as $x |
    ($x | reset) as $t |
    if $t != null and $t >= now and ($x | pct) != null then [($x | pct), $t] else [null, null] end;

  . as $r |
  ((.model.id // "") + " " + (.model.display_name // "") | ascii_downcase) as $m |
  (if ($m | test("claude|sonnet|opus|haiku|gpt|3p")) then "3p" else "gemini" end) as $k |
  (if $k == "3p" then "Claude and GPT models" else "Gemini Models" end) as $gname |
  ($cache | try fromjson catch null) as $c |
  ($r.model.display_name // $r.model.id // "?") as $name |
  ($r.model.effort // $r.effort.level // $r.effort // "" | tostring) as $effort |
  [
    $name,
    (if $effort == "" or $effort == "null" or ($name | ascii_downcase | contains("(" + ($effort | ascii_downcase) + ")")) then "" else $effort end),
    (if $r.context_window.used_percentage != null then ($r.context_window.used_percentage | round)
     elif ($r.context_window.total_input_tokens and ($r.context_window.context_window_size // 0) > 0)
     then ($r.context_window.total_input_tokens / $r.context_window.context_window_size * 100 | round)
     else null end),
    (pick($r; $c; $k; "5h"; $gname)[]),
    (pick($r; $c; $k; "weekly"; $gname)[]),
    (if (bucket($r.quota; $k; "5h") | reset) != null then 1 else 0 end),
    (now | floor)
  ] | map(if . == null then "" else tostring end) | join("\u001f")
' 2>/dev/null <<< "$input")
PARSED=${PARSED//$'\r'/}
IFS=$'\x1f' read -r MODEL_NAME EFFORT CTX H5_USED H5_EPOCH WK_USED WK_EPOCH FRESH NOW <<< "$PARSED"
[[ -z $MODEL_NAME ]] && MODEL_NAME="?"

# Save fresh quota from stdin to the cache for the next new chat (the reader only uses .quota)
if [[ $FRESH == 1 ]]; then
  [[ -d $CACHE_DIR ]] || mkdir -p "$CACHE_DIR" 2>/dev/null
  printf '%s' "$input" > "$USAGE_CACHE" 2>/dev/null
fi

# 3. Formatting and colors. printf %(...)T is a builtin from bash 4.2; macOS /bin/bash (3.2)
#    falls back to date.
if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2) )); then
  fmt_time() { printf -v "$1" "%($2)T" "$3"; }
else
  fmt_time() { local v; v=$(date -r "$3" "+$2" 2>/dev/null || date -d "@$3" "+$2" 2>/dev/null); printf -v "$1" '%s' "$v"; }
fi
RST=$'\033[0m'; DIM=$'\033[2m'
set_color() {
  local p=${1%.*}
  if   (( p >= 80 )); then COLOR=$'\033[31m'
  elif (( p >= 50 )); then COLOR=$'\033[33m'
  else COLOR=$'\033[32m'; fi
}
set_bar() {
  local p=${1%.*} filled i
  BAR=""
  filled=$(( p / 10 )); (( filled > 10 )) && filled=10
  for ((i=0; i<10; i++)); do (( i < filled )) && BAR+="▓" || BAR+="░"; done
}
set_remaining() {
  local s=$(( $1 - NOW ))
  (( s < 0 )) && s=0
  if (( s >= 86400 )); then
    printf -v REM '%dd%dh' $((s/86400)) $((s%86400/3600))
  else
    printf -v REM '%dh%02dm' $((s/3600)) $((s%3600/60))
  fi
}

out="${DIM}${MODEL_NAME}${RST}"
[[ -n $EFFORT ]] && out+=" ${DIM}·${RST} ${EFFORT}"

# Context window usage
if [[ -n $CTX ]]; then
  set_color "$CTX"; set_bar "$CTX"
  out+=" │ ctx ${COLOR}${BAR} ${CTX}%${RST}"
fi

# 5-hour quota
if [[ -n $H5_USED && -n $H5_EPOCH ]]; then
  set_color "$H5_USED"
  out+=" │ 5h ${COLOR}${H5_USED}%${RST}"
  fmt_time h5_time '%H:%M' "$H5_EPOCH"
  set_remaining "$H5_EPOCH"
  [[ -n $h5_time ]] && out+=" ${DIM}↻ ${h5_time} (${REM})${RST}"
fi

# Weekly quota
if [[ -n $WK_USED && -n $WK_EPOCH ]]; then
  set_color "$WK_USED"
  out+=" │ wk ${COLOR}${WK_USED}%${RST}"
  fmt_time wk_raw '%w %d %H:%M' "$WK_EPOCH"
  if [[ -n $wk_raw ]]; then
    d_list=(Sun Mon Tue Wed Thu Fri Sat)
    set_remaining "$WK_EPOCH"
    out+=" ${DIM}↻ ${d_list[${wk_raw%% *}]} ${wk_raw#* } (${REM})${RST}"
  fi
fi

printf '%s\n' "$out"
exit 0
