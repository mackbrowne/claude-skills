---
name: expo-parallel-worktrees
description: Run several Expo / React Native dev instances side by side, one per git worktree or agent session, without Metro port collisions, dev clients loading another checkout's bundle, or sessions killing each other's servers and simulators. Uses expo-harness (deterministic per-worktree Metro port plus a dedicated simulator or emulator) and the strategy behind it. Use when starting Metro or a dev client in a git worktree, when two checkouts or agents need Metro at once, when port 8081 is taken, when a device shows code from the wrong checkout, when an e2e harness must target the right Metro, or when cleaning up stale Metro servers and per-worktree simulators.
---

# Parallel Expo instances across git worktrees

Every checkout of an Expo app defaults to Metro on `8081`. With several worktrees (or several agent sessions) the second Metro prompts for another port, dev clients connect to whichever bundler answers, and one checkout's device runs another checkout's JS while every signal looks healthy. The fix is one isolated instance per worktree: its own stable Metro port and its own device.

## Use expo-harness

[expo-harness](https://github.com/mackbrowne/expo-harness) wraps the project's existing dev command. Nothing is installed into the target repo.

```sh
npx github:mackbrowne/expo-harness -- pnpm dev      # instead of: pnpm dev
npx github:mackbrowne/expo-harness --print-port     # this checkout's port, for other scripts
npx github:mackbrowne/expo-harness ls               # running Metro servers + sims, by branch
npx github:mackbrowne/expo-harness clean --dry-run  # plan a teardown of stale instances
```

- Do NOT run `npx expo-harness`. That npm name belongs to an unrelated placeholder package. Use the `github:` spec, or a local clone (`node <clone>/bin/expo-harness.mjs`).
- The primary checkout keeps `8081` and gets no device orchestration, so wrapping it changes nothing there.
- Reuse the port elsewhere: `RCT_METRO_PORT=$(npx github:mackbrowne/expo-harness --print-port) pnpm e2e:ios`.
- `clean` always prints its plan and asks first. It shuts simulators down but keeps them; deleting needs `--delete-sims` (that throws away the installed dev build).

## The strategy (apply it by hand when the tool does not fit)

1. **Detect a linked worktree.** `git rev-parse --path-format=absolute --git-dir --git-common-dir`: the primary checkout's two paths are equal; a linked worktree's git dir is `<common>/worktrees/<name>`. The primary keeps `8081`.
2. **Derive the port, never store it.** Hash the branch name (FNV-1a) into `8082`-`8181`, so the same branch always gets the same port and the dev client's remembered server URL stays valid. Fall back to the worktree folder name on a detached HEAD. Never put the port in `.env*`: worktree tools that copy gitignored env files spread the primary checkout's port to every worktree. Allow an explicit override for the rare hash collision, and warn if the derived port already answers `/status`.
3. **Inject with `RCT_METRO_PORT`, not `--port`.** Expo reads it whenever the command passes no `--port`, so any dev command (`expo start`, `pnpm dev`, a monorepo filter) picks it up unmodified. Turbo in strict env mode strips it: add it to the task's `passthroughEnv`. Metro config and config plugins cannot set the port, because Expo resolves it before `metro.config.js` loads.
4. **Carry the port in the dev-client deep link.** A dev build compiled against `8081` connects to any port, so changing ports never needs a native rebuild.
   - iOS: `xcrun simctl openurl <udid> "<scheme>://expo-development-client/?url=http%3A%2F%2Flocalhost%3A<port>"`. Run `xcrun simctl launch <udid> <bundleId>` first to avoid the "Open in <app>?" prompt, or tap Open.
   - Android: `adb -s <serial> reverse tcp:<port> tcp:<port>`, then `adb -s <serial> shell am start -a android.intent.action.VIEW -d "<scheme>://expo-development-client/?url=http://localhost:<port>"`.
5. **One device per worktree.** Name simulators after the branch (`expo-harness <branch>`), so they are recognizable and prunable. A script that picks a simulator by a stock name like "iPhone 16" picks at random when two exist. Boot concurrent Android emulators on distinct console ports (`emulator -avd <avd> -port <even port in 5554-5680>`) so each gets its own `emulator-<port>` serial.
6. **Other local services follow the same offset.** If the app talks to a local backend, derive that port from the same worktree offset, keep it independent of Metro's port, and pass it to the app through `app.config.ts` `extra`, not an env file.

## Prove which checkout a device is running

- Which checkout serves a port: `lsof -nP -iTCP:<port> -sTCP:LISTEN`, then `lsof -a -p <pid> -d cwd -Fn`. A Metro process's working directory is its checkout.
- Is it really Metro: `curl -s localhost:<port>/status` returns `packager-status:running`.
- Did the device actually load this bundle: after the deep link, Metro's log must print a fresh `iOS Bundled …` / `Android Bundled …` line. No line means the device is not running your code. A module count that never changes across edits, while a curl of the bundle URL gives a different count, means the installed dev client is serving another checkout's JS: build the client from this checkout with `npx expo run:ios --device <udid>`.
- A copied dev build (`simctl get_app_container` then `simctl install`) is safe only between checkouts with the same native dependencies. Rebuild after any native module change.
- A fresh worktree may not be watched by watchman (edits trigger no bundle event at all): `watchman watch-project <worktree>`, then restart Metro.

## Shared-machine rules (parallel agent sessions)

- Never stop a Metro server, emulator or simulator you did not start. If you are unsure who owns it, leave it and use another port or device.
- Kill by PID from your own port, never by name pattern. `pkill -f 'expo start'` (even with `-P`) killed every Metro on the machine.
  ```sh
  PIDS=$(lsof -nP -tiTCP:<your-port> -sTCP:LISTEN); [ -n "$PIDS" ] && kill $PIDS
  ```
- E2E and other harnesses must take the Metro port as input. A harness that reuses "whatever answers on 8081" serves another worktree's bundle to a freshly built app, and the failure looks exactly like a stale build.
- Do not drive a device another session is using. Pick a free one or the other platform.
- Agent background tasks can reap processes they spawned when the task ends. Start long-lived Metro servers with `nohup … & disown`, and boot an emulator in the same task that uses it.

## Cleaning up after deleted worktrees

- `npx github:mackbrowne/expo-harness clean` finds orphans: Metro processes whose working directory is gone.
- Xcode never expires per-worktree DerivedData (2-9 GB each). Read each dir's `WorkspacePath` with `/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' <dir>/info.plist` and delete only those whose path no longer exists.
- `xcrun simctl delete unavailable` removes only simulators whose runtime is gone. Delete per-worktree simulators by name after their branch is gone.
