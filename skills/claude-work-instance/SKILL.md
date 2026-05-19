---
name: claude-work-instance
description: >-
  Set up a second, isolated Claude on macOS — its own login, history, and
  settings — running alongside the primary one. Two related capabilities:
  (1) a branded Claude Desktop app instance (custom name/icon, single-instance,
  runs next to personal Claude); (2) the Claude Code CLI counterpart — a
  `claude-work` command/alias added to ~/.zshrc or ~/.bashrc with an isolated
  CLAUDE_CONFIG_DIR. Use whenever the user wants to separate work and personal
  Claude, run two Claude Desktops side by side, a dedicated work/client/team
  Claude, a second account without logging out of the first, a custom Claude
  icon or name, a separate Claude Code terminal command, a `claude-work` alias,
  or an isolated CLI profile. Encodes the macOS code-signing/Keychain pitfalls
  that make naive attempts fail silently (login never persists, app hangs), so
  prefer it over ad-hoc attempts whenever the user is on macOS and mentions
  multiple Claude instances, Claude Code CLI accounts, profiles, or
  work/personal separation.
---

# Separate Claude Desktop Instance (macOS)

Create a second Claude Desktop "profile": its own login, chat history, and
settings, with its own name and icon, running as a **single instance**
alongside the user's normal Claude. Classic use: separating **work** and
**personal** Claude accounts.

macOS only. Relies on macOS LaunchServices and Keychain behavior.

## Set expectations honestly, up front

Before building anything, make sure the user knows the one limitation, so they
aren't disappointed later:

- The custom icon and name show in **Finder, Spotlight, Launchpad, the
  Applications folder, and the Dock when the app is not running**.
- While the instance is **running**, the **Dock tile shows the standard Claude
  icon**. This is unavoidable in the robust approach: the instance *is* the
  genuine signed `Claude.app` (that is what keeps login working). A custom
  running-tile icon would require a modified, re-signed ~700 MB copy of
  Claude.app that is fragile (crashes) and breaks on **every** Claude
  auto-update. Do **not** go down the copy/re-sign path unless the user
  explicitly insists and accepts rebuilding it after every update. It is
  almost never worth it; lead with the lightweight approach below.

## Why the launch method is non-negotiable

The instinctive approach — a small `.app` whose executable `exec`s
`/Applications/Claude.app/Contents/MacOS/Claude --user-data-dir=...` — **looks
like it works but breaks authentication in a way that is painful to diagnose.**

macOS ties **Keychain access to an app's code signature**. Electron stores its
cookie/session-encryption key ("Safe Storage") in the Keychain. When you launch
Claude's signed inner binary from a *custom unsigned wrapper*, the process has
an inconsistent code identity, cannot unlock Safe Storage, and: login
**silently never persists**, the app **hangs and retries** (feels very slow),
and under memory pressure it can surface as misleading errors like "Claude Code
couldn't start … binary is missing or damaged".

The fix is to **launch the genuine, signed `Claude.app` as a new instance**
(`open -n -a`) and only change its data directory:

```sh
open -n -a "/Applications/Claude.app" --args \
  --user-data-dir="$HOME/Library/Application Support/Claude-Work"
```

`open -n` starts a fresh instance of the *real* app, so it keeps Claude's
genuine code signature — Keychain/Safe Storage works and the login sticks. A
different `--user-data-dir` makes it a fully separate profile.

## How to use this skill

Run the bundled script `scripts/create-claude-work-instance.sh`. It builds the
wrapper bundle, the single-instance launcher, the icon, and flushes caches.
Do not hand-roll it.

### 1. Collect preferences (ask only what's unstated)

- **Name** (default `Claude Work`) — app filename and Finder/Spotlight label.
- **Icon** (optional) — a square PNG (512px+). If the user has a brand/employer
  logo, use it. If they paste an image rather than give a path, have them save
  it to a file first and pass that path. If none, Claude's icon is reused.
- **Profile directory** (default `~/Library/Application Support/Claude-Work`).
  Give each separate instance a distinct name *and* data dir.

### 2. Run the script

```sh
bash "<skill-path>/scripts/create-claude-work-instance.sh" \
  --name "Claude Work" \
  --icon "/path/to/logo.png"        # omit --icon to reuse Claude's icon
```

Other flags: `--data-dir <path>`, `--target /path/to/Claude.app`, `--help`.
Idempotent — re-running rebuilds the wrapper cleanly.

### 3. Tell the user what to expect

- Launch `<Name>` from `/Applications` / Spotlight / Launchpad.
- **Sign in** — it is a brand-new isolated profile, so they log in with the
  account this instance is for. It will persist.
- It runs **alongside** personal Claude; the two never interfere, and they do
  **not** need to quit one to use the other.
- **Re-launching focuses the existing window** instead of opening another —
  the launcher detects a running instance by its data dir and brings it to the
  front rather than spawning a duplicate.
- Restate the running-Dock-tile limitation from the top section.

## Also: Claude Code CLI work profile (`claude-work` command)

Separate from the Desktop app, the user often *also* wants the **Claude Code
CLI** (`claude` in the terminal) to use a different account/profile for work.
This is **much simpler** than the Desktop app — there is no bundle, no signing,
no Dock. Isolation is purely environment variables, so it is a shell function,
not an app.

Use the bundled script `scripts/add-claude-code-work-alias.sh`. It installs a
`claude-work` shell function into the user's `~/.zshrc` (or `~/.bashrc` /
`~/.bash_profile`, auto-detected) inside a clearly-marked managed block. It is
idempotent (re-running replaces only its own block), backs the rc file up
first, and syntax-checks the result — restoring the backup if the check fails,
so a bad run can never break the user's shell startup.

What the function does:

- Always sets `CLAUDE_CONFIG_DIR` to an isolated dir (default `~/.claude-work`),
  which separates settings, sessions, history, MCP config, and plugins.
- Optionally exports `ANTHROPIC_API_KEY` read from the macOS **Keychain**
  (pass `--api-key-keychain <service>`), then runs `command claude "$@"`.

### The Keychain caveat — state this plainly

On macOS, Claude **subscription (OAuth) logins live in the shared login
Keychain, NOT in `CLAUDE_CONFIG_DIR`**. So two *subscription* accounts cannot
be logged in at the same time — switching means `/logout` then `/login`.
`CLAUDE_CONFIG_DIR` still isolates everything else. For true, friction-free
**side-by-side** work + personal, the work side should use an **API key**
(Console/org key): it takes precedence over the subscription and is not in the
Keychain. The function supports this via `--api-key-keychain`.

### Steps

1. Ask: function name (default `claude-work`), config dir (default
   `~/.claude-work`), and whether work uses an **API key** (recommended for
   simultaneous use — ask if their org has a Console/API key) or a
   **subscription** (accept the switch-requires-relogin caveat).
2. Run, e.g.:
   ```sh
   bash "<skill-path>/scripts/add-claude-code-work-alias.sh" \
     --name claude-work --config-dir "$HOME/.claude-work" \
     --api-key-keychain claude-work-key     # omit for subscription mode
   ```
3. Tell the user to `source` their rc file (or open a new terminal) and verify
   with `type claude-work`. **API-key mode:** the user must add the key to the
   Keychain once themselves — the script prints the exact
   `security add-generic-password -s '<service>' -a "$USER" -w` command. Do
   **not** handle the user's API key/secret yourself; let `security` prompt
   them (it does not echo the secret).

This CLI capability is independent of the Desktop instance — offer it whenever
the user mentions the Claude Code *terminal command*, a `claude-work` alias, or
work/personal CLI accounts, even if they don't want the Desktop app.

## Caveats — state these plainly

- **macOS only.**
- **Running Dock tile shows the standard Claude icon** (see the expectations
  section). Cosmetic; everything else is custom. Do not "fix" it with a copy.
- **Resource cost:** each instance is a full Electron app (~1 GB+ RAM and a
  dozen helper processes). Two at once on a RAM-starved Mac will swap and
  freeze. If the new instance is sluggish or "won't load", it is almost always
  memory pressure — advise closing heavy apps (Chrome especially), not
  rebuilding.
- **Auto-updates:** the wrapper points at `/Applications/Claude.app`, so
  Claude's normal auto-updates apply automatically. Never rebuild for updates.
- **Uninstall (Desktop):** `rm -rf "/Applications/<Name>.app" "<data-dir>"`.
- **Uninstall (CLI):** delete the marked `>>> claude-work …` block from the rc
  file (a timestamped `.bak.cwskill.*` backup is kept), and optionally
  `rm -rf ~/.claude-work`.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Signs in, then logged out again; app hangs | Wrong launch method (exec'd inner binary from unsigned wrapper) | Ensure the launcher uses `open -n -a "...Claude.app" --args --user-data-dir=...`. Re-run the script. |
| Re-launching opens another window each time | Launcher missing the single-instance guard | Use this skill's script — its launcher focuses the existing instance by matching the running process's `--user-data-dir`. |
| Custom icon not showing in Finder/Dock | Icon cache stale | Re-run the script (flushes caches + re-registers); or right-click the app → Get Info; or log out/in. |
| "Claude Code couldn't start / binary missing or damaged" | Usually memory pressure, not real corruption | Free RAM (quit Chrome/other Electron apps); retry. Confirm binary is fine with `codesign --verify`. |
| Both instances feel slow | Two full Electron suites on limited RAM | Close other heavy apps, or run one at a time. Not a config bug. |
| User wants the running Dock tile icon custom too | Requires modified re-signed copy of Claude.app | Explain it is fragile and breaks on every Claude update. Only attempt if the user insists and accepts that maintenance burden. |
| `claude-work: command not found` | rc file not reloaded | `source ~/.zshrc` (or the targeted rc) or open a new terminal; verify with `type claude-work`. |
| `claude-work` shows the personal/wrong account | Subscription creds are shared in the macOS Keychain (not isolated by `CLAUDE_CONFIG_DIR`) | Use an API key for work via `--api-key-keychain`, or `/logout` then `/login` when switching subscription accounts. |
| `claude-work` errors: "no API key in Keychain service …" | Keychain item not added yet | Run the printed `security add-generic-password -s '<service>' -a "$USER" -w` once (user pastes the key; it is not echoed). |
