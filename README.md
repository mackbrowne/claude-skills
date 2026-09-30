# claude-skills

A personal collection of [Claude](https://claude.com) skills (for Claude Code
and Claude Desktop). Each skill is a self-contained folder under `skills/` with
a `SKILL.md` plus any bundled scripts.

## Skills

| Skill | What it does |
|---|---|
| [`claude-work-instance`](skills/claude-work-instance) | **macOS.** Sets up a separate, branded Claude Desktop instance with a fully isolated profile (own login/history/settings, single-instance, runs next to personal Claude) **and** a `claude-work` Claude Code CLI command/alias with an isolated `CLAUDE_CONFIG_DIR`. Encodes the macOS code-signing/Keychain pitfalls that make naive attempts fail silently. |
| [`expo-parallel-worktrees`](skills/expo-parallel-worktrees) | **Expo / React Native.** Runs one isolated dev instance per git worktree or agent session: a deterministic Metro port and a dedicated simulator/emulator via [expo-harness](https://github.com/mackbrowne/expo-harness), plus the strategy behind it, how to prove which checkout a device is running, and rules for sharing one machine between parallel sessions. |

## Installing a skill

Packaged `.skill` files live in [`dist/`](dist/) and are attached to GitHub
Releases. A `.skill` is just a zip of the skill folder, and every `SKILL.md` is
human-readable on its own.

To use one locally, place the skill folder where your Claude loads skills from
(or import the `.skill` via your Claude Code skills/plugins), then invoke it by
describing the task — e.g. *"set up a separate work Claude"*.

Each skill's `SKILL.md` documents exactly what it does and any caveats. Read it
before running bundled scripts; some make system changes (e.g. creating apps in
`/Applications`, editing your shell rc file). Scripts are written to be
idempotent and to back up anything they modify.

## Developing

```
skills/<name>/
  SKILL.md            # required: YAML frontmatter (name, description) + body
  scripts/            # optional bundled scripts
  references/ assets/  # optional
```

- `bash tools/package.sh` builds `dist/<name>.skill` for every skill.
- `python3 tools/validate.py` checks each `SKILL.md` (name present;
  description present and ≤ 1024 chars — the triggering-description limit).
- CI runs `shellcheck` + `validate.py` on every push/PR. Pushing a `v*` tag
  packages all skills and attaches the `.skill` files to a GitHub Release.

## License

MIT © 2026 Mack Browne
