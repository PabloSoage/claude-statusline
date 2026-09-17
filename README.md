# Claude Code status line: context and quotas

```
Opus 5 · high │ ctx ▓▓▓░░░░░░░ 34% │ 5h 22% ↻ 12:50 (2h20m) │ wk 40% ↻ mar 22 12:00 (5d1h) │ fable 22% ↻ mar 22 11:59
```

- **effort**: the session's reasoning level (`low` … `max`), also updates after changing it with `/effort`.
  Doesn't appear if the model doesn't support effort.
- **ctx**: % of context used.
- **5h**: % of the session quota, reset time, and time remaining.
- **wk**: % of the weekly quota, reset day and time, and time remaining.
- **fable**: % of the weekly Fable quota and its reset time.
- Colors: green < 50%, yellow < 80%, red from 80% up.

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
  macOS that token lives in the Keychain (`Claude Code-credentials`); on Windows it's read
  directly from `~/.claude/.credentials.json` (`.claudeAiOauth.accessToken`), which Claude
  Code stores there unencrypted. It's cached for 5 minutes in `~/.claude/cache/usage.json`
  and refreshed in the background, so it can lag up to 5 minutes behind. If Anthropic
  changes that endpoint, this segment just disappears without breaking the rest. If your
  account has no Fable-specific quota, this segment simply doesn't appear.
- `refreshInterval: 60` repaints the bar every minute even if you're not using Claude, so
  the countdown keeps advancing.

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
- **Dynamic model quota switching**:
  - Gemini models (`Gemini 3.8 Flash`, `Gemini 3.1 Pro`, etc.) track the **Gemini Models** quota group (`gemini-5h`, `gemini-weekly`).
  - Claude and GPT models (`Claude Sonnet 4.6`, `Claude Opus 4.6`, `GPT-OSS 120B`) switch to the **Claude and GPT models** quota group (`3p-5h`, `3p-weekly`).
- **Background usage cache**: Caches `/usage` responses in `~/.gemini/antigravity-cli/cache/usage.json` refreshed every 5 minutes in the background (`MSYS_NO_PATHCONV=1 agy -p "/usage" --output-format json`).

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
