#!/bin/bash
# Create a separate, branded Claude Desktop instance on macOS with an isolated
# profile (its own login, chat history, settings). Runs alongside personal
# Claude, as a SINGLE instance (re-launching focuses it, never duplicates).
#
# APPROACH: a tiny wrapper .app that launches the GENUINE signed Claude.app as
# a new instance pointed at a separate --user-data-dir. This is deliberately
# the LIGHTWEIGHT, ROBUST approach. Read the next two notes before changing it.
#
# WHY launch the genuine app (do NOT exec Claude's inner binary):
#   macOS ties Keychain access to code signature. Electron stores its
#   cookie/session-encryption key ("Safe Storage") in the Keychain. If you
#   exec /Applications/Claude.app/Contents/MacOS/Claude from a custom UNSIGNED
#   wrapper, the process has an inconsistent code identity, cannot unlock Safe
#   Storage, and login SILENTLY never persists (app hangs / retries forever).
#   `open -n -a "/Applications/Claude.app"` starts a new instance of the REAL
#   signed app, so its code identity is intact and the work login sticks.
#
# WHY NOT a full re-signed copy (so the running Dock tile shows a custom icon):
#   That requires modifying Claude.app's bundle, which breaks Apple's
#   signature, forcing an ad-hoc re-sign of a ~700MB Electron app with many
#   nested helpers. It is fragile (crashes) AND it breaks on every Claude
#   auto-update (the copy is frozen and must be rebuilt each time). It is not
#   worth it. The custom icon on the *running* Dock tile is a known, accepted
#   limitation of this lightweight approach. Do NOT pursue the copy route
#   unless the user explicitly insists and accepts rebuilding after every
#   Claude update.
#
# Usage:
#   create-claude-work-instance.sh [options]
#     --name <name>       Display name & app filename  (default: "Claude Work")
#     --data-dir <path>   Isolated profile directory
#                         (default: ~/Library/Application Support/Claude-Work)
#     --icon <png>        Square PNG (>=512px) for the app icon. If omitted,
#                         reuses Claude's icon.
#     --target <app>      Path to the real Claude.app
#                         (default: /Applications/Claude.app)
#     -h | --help         Show this help and exit
set -euo pipefail

NAME="Claude Work"
DATA_DIR="$HOME/Library/Application Support/Claude-Work"
ICON_PNG=""
TARGET_APP="/Applications/Claude.app"

while [ $# -gt 0 ]; do
  case "$1" in
    --name)     NAME="$2"; shift 2 ;;
    --data-dir) DATA_DIR="$2"; shift 2 ;;
    --icon)     ICON_PNG="$2"; shift 2 ;;
    --target)   TARGET_APP="$2"; shift 2 ;;
    -h|--help)  sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

[ "$(uname)" = "Darwin" ] || { echo "ERROR: macOS only." >&2; exit 1; }
[ -d "$TARGET_APP" ] || { echo "ERROR: Claude.app not found at: $TARGET_APP" >&2; exit 1; }
if [ -n "$ICON_PNG" ] && [ ! -f "$ICON_PNG" ]; then
  echo "ERROR: icon file not found: $ICON_PNG" >&2; exit 1
fi

APP="/Applications/${NAME}.app"
EXE="$(echo "$NAME" | tr -cd '[:alnum:]')"; [ -n "$EXE" ] || EXE="ClaudeInstance"
SLUG="$(echo "$EXE" | tr '[:upper:]' '[:lower:]')"
BUNDLE_ID="com.local.claude.${SLUG}"

if [ -n "$ICON_PNG" ]; then ICON_DESC="$ICON_PNG"; else ICON_DESC="(reusing Claude default icon)"; fi
echo ">> Creating: $APP"
echo "   profile : $DATA_DIR"
echo "   icon    : $ICON_DESC"

# --- (re)build the wrapper bundle -------------------------------------------
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>${NAME}</string>
  <key>CFBundleDisplayName</key><string>${NAME}</string>
  <key>CFBundleExecutable</key><string>${EXE}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleIconFile</key><string>electron.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleVersion</key><string>2.0</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>LSMinimumSystemVersion</key><string>10.13</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
</dict></plist>
PLIST

# Launcher: single-instance. If a process is already running with THIS data
# dir, focus that exact instance instead of spawning a duplicate. Otherwise
# launch the genuine signed Claude.app as a new instance ( -n ) pointed at the
# isolated profile, so Keychain/Safe Storage works and the login persists.
cat > "$APP/Contents/MacOS/${EXE}" <<SCRIPT
#!/bin/sh
WORK="${DATA_DIR}"
PID=\$(pgrep -f -- "--user-data-dir=\$WORK" | head -1)
if [ -n "\$PID" ]; then
  osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is \$PID) to true" 2>/dev/null
  exit 0
fi
exec /usr/bin/open -n -a "${TARGET_APP}" --args --user-data-dir="\$WORK"
SCRIPT
chmod +x "$APP/Contents/MacOS/${EXE}"

# --- icon --------------------------------------------------------------------
if [ -n "$ICON_PNG" ]; then
  TMP="$(mktemp -d)"; IS="$TMP/icon.iconset"; mkdir -p "$IS"
  for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 \
              256:128x128@2x 256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
    sips -s format png -z "${spec%%:*}" "${spec%%:*}" "$ICON_PNG" \
      --out "$IS/icon_${spec##*:}.png" >/dev/null
  done
  iconutil -c icns "$IS" -o "$APP/Contents/Resources/electron.icns"
  rm -rf "$TMP"
else
  cp "$TARGET_APP/Contents/Resources/electron.icns" \
     "$APP/Contents/Resources/electron.icns" 2>/dev/null || true
fi

# --- register + flush icon caches so Finder/Dock pick it up -----------------
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" || true
rm -rf "$HOME/Library/Caches/com.apple.iconservices.store" 2>/dev/null || true
killall Dock Finder 2>/dev/null || true

cat <<DONE

Done.

  App:      $APP
  Profile:  $DATA_DIR  (created on first launch)

Next steps:
  1. Launch "$NAME" from /Applications (or Spotlight / Launchpad).
  2. Sign in -- it's a fresh isolated profile; the login will persist.
  3. Runs alongside personal Claude; re-launching focuses it (no duplicates).

Known limitation (by design):
  The "$NAME" icon shows in Finder, Spotlight, Launchpad, the Applications
  folder, and the Dock when not running. While RUNNING, the Dock tile shows
  the standard Claude icon -- because it is the genuine signed Claude.app,
  which is exactly what keeps the login working. Making the running tile
  custom would require a fragile re-signed 700MB copy that breaks on every
  Claude update; this skill intentionally does not do that.

Other notes:
  - Auto-updates: points at $TARGET_APP, so Claude updates apply automatically.
  - If the icon looks stale: right-click the app > Get Info, or log out/in.
  - Uninstall: rm -rf "$APP" "$DATA_DIR"
DONE
