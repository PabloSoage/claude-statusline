# Claude Code status line: context and quotas

```
Opus 5 · high │ ctx ▓▓▓░░░░░░░ 34% │ 5h 22% ↻ 12:50 (2h20m) │ wk 40% ↻ mar 22 12:00 (5d1h) │ fable 22% ↻ mar 22 11:59 │ cache ● 1h ↻ 47m12s
```

- **effort**: the session's reasoning level (`low` … `max`), also updates after changing it with `/effort`.
  Doesn't appear if the model doesn't support effort.
- **ctx**: % of context used.
- **5h**: % of the session quota, reset time, and time remaining.
- **wk**: % of the weekly quota, reset day and time, and time remaining. With several accounts
  (see [Multiple accounts](#multiple-accounts)) the label carries the account number: `wk2`, `wk3`…
- **fable**: % of the weekly Fable quota and its reset time.
- **cache**: how much longer Anthropic's prompt cache for this session stays warm — a pie glyph
  (`●◕◑◔`, full right after a cache hit/write, thinning out as it approaches expiry), the TTL in play
  (`5m` or `1h`), and the time left before it expires.
- **other accounts** (only with [multiple accounts](#multiple-accounts)): the weekly quota of every
  other account on the machine, e.g. `wk 100% · wk3 5% · wk4 3%`.
- Colors: green < 50%, yellow < 80%, red from 80% up (for **cache**, that's % of the TTL already elapsed).

## Requirements

- **macOS**: uses `security`, `date -r`, and `stat -f`.
- **Windows**: uses Git Bash (bundled with Git for Windows), GNU `date`/`stat`, and reads
  the token directly from `~/.claude/.credentials.json` (Windows has no Keychain).
  Claude Code detects Git Bash on its own and runs the script with it even though
  `statusLine.command` doesn't mention it.
- Linux: untested, but since it uses GNU `date`/`stat` (same as the Windows branch), it
  should work without changes.
- `jq` and `curl`. On macOS: `brew install jq`. On Windows, if you don't have `jq` on your
  PATH, download `jq-windows-amd64.exe` from https://github.com/jqlang/jq/releases and
  place it at `~/.local/bin/jq.exe` — the script and `install.sh` look for it there
  automatically if `jq` isn't found on PATH.
- Claude Code signed in with a **Pro or Max** claude.ai subscription (without it there are
  no quotas; only model and context are shown).

## Quick install

```bash
cd ~/Downloads/claude-statusline   # or wherever you kept the folder
./install.sh
```

On Windows, run that from Git Bash (not PowerShell or cmd).

Copies the script to `~/.claude/statusline.sh`, adds `statusLine` to
`~/.claude/settings.json` (backing up a copy to `settings.json.bak` first), and runs a
test.

If macOS says the file came from the internet and won't let it run:
`xattr -dr com.apple.quarantine ~/Downloads/claude-statusline`

## Manual install

1. Copy the script:
   ```bash
   cp statusline.sh ~/.claude/statusline.sh && chmod +x ~/.claude/statusline.sh
   ```
2. Add to `~/.claude/settings.json` (inside the root object):
   ```json
   "statusLine": {
     "type": "command",
     "command": "~/.claude/statusline.sh",
     "padding": 0,
     "refreshInterval": 60
   }
   ```
3. Open Claude Code. The status line appears without restarting anything if it was
   already open.

## How it works

- **effort, ctx, 5h, and wk** come from the JSON that Claude Code passes to the script
  over stdin (`effort.level`, `context_window.used_percentage`, `rate_limits.five_hour`,
  `rate_limits.seven_day`).
- Before a session's first response, that JSON carries no quotas: 5h and wk are taken
  from the usage-endpoint cache (if their reset has already passed, they aren't shown),
  and ctx shows as 0%.
- **fable** isn't in that JSON. It's read from the endpoint used by `/usage`
  (`api.anthropic.com/api/oauth/usage`, **undocumented**) using Claude Code's token. On
  macOS that token lives in the Keychain (`Claude Code-credentials`, with a suffix when
  `CLAUDE_CONFIG_DIR` is set, see below); on Windows it's read
  directly from `~/.claude/.credentials.json` (`.claudeAiOauth.accessToken`), which Claude
  Code stores there unencrypted. It's cached for 5 minutes in `~/.claude/cache/usage.json`
  and refreshed in the background, so it can lag up to 5 minutes behind. If Anthropic
  changes that endpoint, this segment just disappears without breaking the rest. If your
  account has no Fable-specific quota, this segment simply doesn't appear.
- **cache** is unrelated to the `usage.json` file above — it's Anthropic's server-side prompt cache for
  the conversation. Claude Code caches the prompt with a 1-hour TTL by default, dropping to 5 minutes if
  the account is in usage overage; this isn't in the stdin JSON, so the script finds it by reading the
  tail of the session's transcript (`transcript_path` from stdin) for the last message with cache
  activity (`message.usage.cache_read_input_tokens` or `cache_creation_input_tokens`), and the TTL is
  read off the most recent `cache_creation.ephemeral_1h_input_tokens` / `ephemeral_5m_input_tokens` in
  that same window. It disappears once nothing to base the countdown on has been found yet (no cache
  activity in the last 500 transcript lines) or once the cache has already expired.
- `refreshInterval: 60` repaints the bar every minute even if you're not using Claude, so
  the countdown keeps advancing.
- If `CLAUDE_CONFIG_DIR` is set, credentials and the usage cache are read from that account
  instead of `~/.claude`, so each account shows its own quotas (see below).

## Multiple accounts

If you switch between several Claude accounts with `CLAUDE_CONFIG_DIR` (e.g. an alias
`claude2='CLAUDE_CONFIG_DIR=$HOME/.claude2 claude'`), the status line tells them apart:

```
claude3:  … │ wk3 5% ↻ mié 28 07:00 (4d20h) │ fable 0% │ cache ● 1h ↻ 52m10s │ wk 100% · wk2 71% · wk4 3%
```

- **Which account this is:** `wk` for `~/.claude`, `wkN` for a config dir whose name ends in a
  number (`~/.claude2`, `~/.claude-account3`…).
- **The others at the end:** every config dir found on the machine (`~/.claude`, plus any
  `~/.claude[0-9]*` or `~/.claude-*[0-9]` with its own `.claude.json`) with its weekly quota. Each one's usage cache is refreshed
  in the background every 5 minutes with that account's own token, so the numbers are live even
  if that account has no session open. Accounts without a login, or whose cached week has
  already reset, are left out.
- **Credentials per account:** on Windows/Linux, `$CLAUDE_CONFIG_DIR/.credentials.json`. On macOS,
  Claude Code stores each config dir in its own Keychain entry,
  `Claude Code-credentials-<first 8 hex chars of sha256 of the CLAUDE_CONFIG_DIR path>`;
  `~/.claude` (no `CLAUDE_CONFIG_DIR`) uses plain `Claude Code-credentials`.
- **Optional: show the account's email.** Set `STATUSLINE_ACCOUNT` in the status line command:

  ```json
  "command": "STATUSLINE_ACCOUNT=user ~/.claude/statusline.sh"
  ```

  | `STATUSLINE_ACCOUNT` | Label |
  | --- | --- |
  | unset (default) | `wk3` |
  | `email` | `wk3 (jane.doe7@example.com)` |
  | `user` | `wk3 (jane.doe7)` |
  | `num` | `wk3 (7)`, the digits at the end of the part before the `@` (nothing if there are none) |

  The email is read from `oauthAccount.emailAddress` in `~/.claude.json` (or
  `$CLAUDE_CONFIG_DIR/.claude.json`), so it follows whatever account each alias is signed in with.

### Setting up an extra account

Each account is its own config dir, and `CLAUDE_CONFIG_DIR` points Claude Code at it. The login
stays per dir (its own Keychain entry on macOS, its own `.credentials.json` elsewhere), and
everything else is symlinked to `~/.claude`, so memory, sessions (`/resume`), skills, settings and
this status line are shared by all accounts.

| Shared (symlinked to `~/.claude`) | Per account (never link these) |
| --- | --- |
| `projects/` (memory and transcripts), `history.jsonl`, `plans/`, `todos/`, `file-history/`, `paste-cache/`, `CLAUDE.md`, `settings.json`, `keybindings.json`, `statusline.sh`, `skills/`, `commands/`, `agents/`, `plugins/`, `hooks/`, `workflows/` | `.claude.json` (account, MCP servers, trusted folders), `.credentials.json` (the login on Windows/Linux), `backups/` (copies of `.claude.json`: if shared, Claude Code could restore another account's), `cache/` (that account's usage), sessions and other runtime state |

Use one account at a time per project: they all write the same memory and transcripts.

#### macOS and Linux

```bash
N=2                                   # creates ~/.claude2 and the command claude2
S="$HOME/.claude"; D="$HOME/.claude$N"
mkdir -p "$D"
for f in projects plans todos file-history paste-cache skills commands agents plugins hooks workflows; do
  mkdir -p "$S/$f"; [ -e "$D/$f" ] || ln -s "$S/$f" "$D/$f"
done
for f in history.jsonl CLAUDE.md settings.json keybindings.json statusline.sh; do
  [ -e "$S/$f" ] && [ ! -e "$D/$f" ] && ln -s "$S/$f" "$D/$f"
done
# Its own .claude.json, without the account, so MCP servers and trusted folders carry over
[ -f "$D/.claude.json" ] || (umask 077 && jq '{hasCompletedOnboarding, lastOnboardingVersion,
  installMethod, autoUpdates, mcpServers, projects}' ~/.claude.json > "$D/.claude.json")
# The launcher (works from scripts and IDEs too); it takes N from its own file name
mkdir -p ~/.local/bin
cat > ~/.local/bin/claude$N <<'EOF'
#!/usr/bin/env bash
# claudeN: Claude Code with the account in ~/.claudeN
dir="$HOME/.claude${0##*/claude}"
# See "Memory writes asking for permission" below
settings=()
if [[ " $* " != *" --settings "* ]]; then
  root=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [[ $root == */.git ]]; then root=${root%/.git}
  else root=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P); fi
  key=$(printf '%s' "$root" | sed 's/[^A-Za-z0-9]/-/g')
  settings=(--settings "{\"autoMemoryDirectory\":\"$HOME/.claude/projects/$key/memory\"}")
fi
exec env CLAUDE_CONFIG_DIR="$dir" claude ${settings[@]+"${settings[@]}"} "$@"
EOF
chmod +x ~/.local/bin/claude$N
```

Then run `claude2`, `/login` with the other account (check the browser shows the right one), and
confirm with `claude2 auth status` that each command reports its own email. `~/.local/bin` must be
on your `PATH` (the native installer already puts `claude` there). A plain alias
(`alias claude2='CLAUDE_CONFIG_DIR="$HOME/.claude2" claude'`) also works, but then every memory
write asks for permission (see below). On Linux the login lives in `~/.claude2/.credentials.json`:
never symlink that file.

#### Windows (PowerShell)

Directories are linked with junctions (no admin rights needed); files with symbolic links, which
need *Settings → For developers → Developer Mode* (otherwise use `HardLink`, but an editor that
saves by replacing the file breaks a hard link, and the copies drift apart).

```powershell
$N = 2
$S = "$env:USERPROFILE\.claude"; $D = "$env:USERPROFILE\.claude$N"
New-Item -ItemType Directory -Force $D | Out-Null
foreach ($f in 'projects','plans','todos','file-history','paste-cache','skills','commands','agents','plugins','hooks','workflows') {
  New-Item -ItemType Directory -Force "$S\$f" | Out-Null
  if (-not (Test-Path "$D\$f")) { New-Item -ItemType Junction -Path "$D\$f" -Target "$S\$f" | Out-Null }
}
foreach ($f in 'history.jsonl','CLAUDE.md','settings.json','keybindings.json','statusline.sh') {
  if ((Test-Path "$S\$f") -and -not (Test-Path "$D\$f")) {
    New-Item -ItemType SymbolicLink -Path "$D\$f" -Target "$S\$f" | Out-Null
  }
}
# Its own .claude.json, without the account (written as UTF-8 without BOM)
if (-not (Test-Path "$D\.claude.json")) {
  $j = Get-Content "$env:USERPROFILE\.claude.json" -Raw | ConvertFrom-Json |
    Select-Object hasCompletedOnboarding, lastOnboardingVersion, installMethod, autoUpdates, mcpServers, projects
  [IO.File]::WriteAllText("$D\.claude.json", ($j | ConvertTo-Json -Depth 100))
}
# The command: a function in your PowerShell profile
Add-Content $PROFILE @"

function claude$N {
  `$old = `$env:CLAUDE_CONFIG_DIR; `$env:CLAUDE_CONFIG_DIR = "`$env:USERPROFILE\.claude$N"
  # See "Memory writes asking for permission" below; a settings file avoids quoting JSON
  `$root = git rev-parse --path-format=absolute --git-common-dir 2>`$null
  if (`$root -match '[\\/]\.git$') { `$root = `$root -replace '[\\/]\.git$', '' }
  else { `$root = git rev-parse --show-toplevel 2>`$null; if (-not `$root) { `$root = (Get-Location).Path } }
  `$key = `$root -replace '[^A-Za-z0-9]', '-'
  `$mem = ("`$env:USERPROFILE\.claude\projects\`$key\memory" -replace '\\', '/')
  `$cfg = "`$env:TEMP\claude$N-memory-`$key.json"
  [IO.File]::WriteAllText(`$cfg, "{``"autoMemoryDirectory``": ``"`$mem``"}")
  try { claude --settings `$cfg @args } finally { `$env:CLAUDE_CONFIG_DIR = `$old }
}
"@
```

Open a new PowerShell, run `claude2` and `/login`. The `try/finally` restores the variable, so
plain `claude` keeps using the first account in the same window. Never link `.credentials.json`
or `.claude.json`. Don't remove a junction with `Remove-Item -Recurse` (PowerShell 5.1 can delete
the target's contents); plain `Remove-Item` removes only the link. From Git Bash or WSL, follow the
Linux steps instead (WSL has its own `~`, separate from Windows'). The Windows steps haven't
been tested on a real machine yet.

#### Memory writes asking for permission

Seen from an extra account, its memory folder (`~/.claude2/projects/<project>/memory`) goes
through the `projects` symlink into `~/.claude`, another account's config dir. Claude Code treats
that as a sensitive file and asks before every memory write (`… resolves through a symlink to
~/.claude/projects/…`), which can leave an agent waiting for hours. Allow rules and
`additionalDirectories` don't lift this check.

The launchers above avoid it by passing `autoMemoryDirectory` with the real path: the one
`~/.claude` itself uses for the project you start in (the main repository's root, also from a
subfolder or a git worktree; outside git, the current directory, with every character other than
a letter or digit turned into `-`). Memory writes are then allowed without asking and land in the
same files as with the main account. If you pass your own `--settings`, the launcher leaves it
alone. Sessions started before installing the launcher keep asking until they're restarted.

## Notes

- The first time, macOS may ask for permission for `security` to read the Keychain:
  "Always Allow."
- The token is only ever sent to `api.anthropic.com`; it's never written to disk or
  printed.
- With the status line active, some hints in Claude Code's footer disappear (e.g.
  `esc to interrupt`).
- To uninstall: remove the `statusLine` key from `~/.claude/settings.json` and delete
  `~/.claude/statusline.sh`.

---

# Google Antigravity CLI (`agy`) status line

Status line support for **Google Antigravity CLI (`agy`)**, showing context usage and quotas adapted dynamically to the active model.

```
Gemini 3.8 Flash (Medium) │ ctx ▓▓░░░░░░░░ 25% │ 5h 17% ↻ 23:25 (4h41m) │ wk 3% ↻ Wed 23 18:34 (5d23h)
```
or when switching to Claude/GPT in Antigravity:
```
Claude Sonnet 4.6 (Thinking) · high │ ctx ▓▓▓▓░░░░░░ 40% │ 5h 0% ↻ 23:40 (4h56m) │ wk 0% ↻ Thu 24 18:40 (6d23h)
```

## Features

- **effort**: Active reasoning effort level (`low`, `medium`, `high`).
- **ctx**: Percentage of context window used with a 10-block progress bar `▓░`.
- **5h**: Percentage of session quota used, reset time (`HH:MM`), and time remaining `(XhYYm)`.
- **wk**: Percentage of weekly quota used, reset day/time (`Day dd HH:MM`), and time remaining `(XdYh)`.
- No **cache** segment here: `agy` wraps several model providers (Gemini, Claude, GPT) and doesn't
  expose a per-conversation prompt-cache TTL the way Claude Code's own transcript does, so this script
  doesn't attempt to guess one.
- **Dynamic model quota switching**:
  - Gemini models (`Gemini 3.8 Flash`, `Gemini 3.1 Pro`, etc.) track the **Gemini Models** quota group (`gemini-5h`, `gemini-weekly`).
  - Claude and GPT models (`Claude Sonnet 4.6`, `Claude Opus 4.6`, `GPT-OSS 120B`) switch to the **Claude and GPT models** quota group (`3p-5h`, `3p-weekly`).
- **Direct quota consumption**: Uses live quota metrics injected directly by Antigravity CLI via stdin (`.quota`), falling back to local cached usage if available without spawning background subshells (preventing command runner timeouts on Windows Git Bash).

## Quick install (Antigravity)

```bash
cd ~/Downloads/claude-statusline   # or repository path
./install-antigravity.sh
```

On Windows, run from Git Bash.

Copies `statusline-antigravity.sh` to `~/.antigravity-statusline/statusline.sh` and configures `statusLine` in `~/.gemini/antigravity-cli/settings.json`.

## Manual install (Antigravity)

1. Copy the script:
   ```bash
   mkdir -p ~/.antigravity-statusline
   cp statusline-antigravity.sh ~/.antigravity-statusline/statusline.sh && chmod +x ~/.antigravity-statusline/statusline.sh
   ```
2. Add to `~/.gemini/antigravity-cli/settings.json`:
   ```json
   "statusLine": {
     "command": "bash ~/.antigravity-statusline/statusline.sh",
     "enabled": true
   }
   ```
3. Open `agy`. The status line will render at the bottom. You can also toggle it via `/statusline`.
