#!/bin/bash
# Add a `claude-work` shell function to the user's shell rc file so the Claude
# Code CLI runs with an ISOLATED work profile (separate settings, sessions,
# history via CLAUDE_CONFIG_DIR) and, optionally, a work API key pulled from
# the macOS Keychain.
#
# This is the CLI counterpart to the Desktop "Claude Work" instance. Unlike the
# Desktop app there is NO bundle/signing involved -- isolation is just env vars.
#
# KEYCHAIN CAVEAT (state this to the user): on macOS, Claude *subscription*
# (OAuth) logins live in the shared login Keychain, NOT in CLAUDE_CONFIG_DIR.
# So two subscription accounts cannot be logged in simultaneously -- switching
# means /logout + /login. To run work + personal truly side by side without
# re-login, the work side should use an API key (Console/org key); it takes
# precedence over the subscription and is not in the Keychain.
#
# Usage:
#   add-claude-code-work-alias.sh [options]
#     --name <name>          Function/command name      (default: claude-work)
#     --config-dir <path>    Isolated CLI profile dir    (default: ~/.claude-work)
#     --api-key-keychain <s> Keychain *service name* holding the work API key.
#                            If set, the function exports ANTHROPIC_API_KEY from
#                            `security find-generic-password -s <s> -w`.
#                            If omitted, subscription mode (CLAUDE_CONFIG_DIR
#                            only; you /login inside the work profile).
#     --rc <path>            Target rc file (default: auto from $SHELL)
#     -h | --help            Show this help and exit
#
# Idempotent: re-running replaces its own managed block (per --name); it never
# touches unrelated lines, backs the rc file up first, and syntax-checks the
# result (restoring the backup if the check fails).
set -euo pipefail

NAME="claude-work"
CONFIG_DIR="$HOME/.claude-work"
KEYCHAIN_SVC=""
RC=""

while [ $# -gt 0 ]; do
  case "$1" in
    --name)             NAME="$2"; shift 2 ;;
    --config-dir)       CONFIG_DIR="$2"; shift 2 ;;
    --api-key-keychain) KEYCHAIN_SVC="$2"; shift 2 ;;
    --rc)               RC="$2"; shift 2 ;;
    -h|--help)          sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

[ "$(uname)" = "Darwin" ] || echo "NOTE: written for macOS; Keychain bits are macOS-only." >&2

# --- pick the rc file --------------------------------------------------------
SHELL_KIND="bash"
case "${SHELL:-}" in
  */zsh)  SHELL_KIND="zsh" ;;
  */bash) SHELL_KIND="bash" ;;
esac
if [ -z "$RC" ]; then
  if [ "$SHELL_KIND" = "zsh" ]; then
    RC="$HOME/.zshrc"
  elif [ -f "$HOME/.bash_profile" ]; then
    RC="$HOME/.bash_profile"   # macOS Terminal bash is a login shell
  else
    RC="$HOME/.bashrc"
  fi
fi
case "$RC" in *zsh*) CHECK_SHELL="zsh" ;; *) CHECK_SHELL="bash" ;; esac
touch "$RC"

echo ">> Target rc : $RC"
echo "   function  : $NAME"
echo "   config dir : $CONFIG_DIR"
echo "   auth mode  : $([ -n "$KEYCHAIN_SVC" ] && echo "API key from Keychain service '$KEYCHAIN_SVC'" || echo "subscription (CLAUDE_CONFIG_DIR only)")"

# --- back up ----------------------------------------------------------------
BAK="${RC}.bak.cwskill.$(date +%Y%m%d-%H%M%S)"
cp "$RC" "$BAK"
echo ">> Backup    : $BAK"

# --- strip any previous managed block for THIS name -------------------------
BEGIN_MARK="# >>> ${NAME} (managed by claude-work-instance skill) >>>"
END_MARK="# <<< ${NAME} (managed by claude-work-instance skill) <<<"
awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
  $0==b {skip=1; next}
  skip && $0==e {skip=0; next}
  !skip {print}
' "$RC" > "${RC}.cwtmp"

# --- append a fresh managed block -------------------------------------------
{
  cat "${RC}.cwtmp"
  printf '\n%s\n' "$BEGIN_MARK"
  cat <<BLOCK
# Claude Code CLI with an isolated work profile. Safe to edit values below.
${NAME}() {
  local _cfg="${CONFIG_DIR}"
  local _svc="${KEYCHAIN_SVC}"
  local _bin _key=""
  # Resolve a claude binary: prefer one on PATH; else the newest
  # Claude-Desktop-managed copy (it auto-updates, so glob the latest).
  _bin="\$(command -v claude 2>/dev/null || true)"
  if [ -z "\$_bin" ]; then
    _bin="\$(ls -1dt "\$HOME/Library/Application Support/Claude/claude-code/"*/claude.app/Contents/MacOS/claude 2>/dev/null | head -1)"
  fi
  if [ -z "\$_bin" ]; then
    echo "${NAME}: no 'claude' binary found. Install the Claude Code CLI, or open Claude Desktop once so it fetches one." >&2
    return 1
  fi
  if [ -n "\$_svc" ]; then
    _key="\$(security find-generic-password -s "\$_svc" -w 2>/dev/null)"
    if [ -z "\$_key" ]; then
      echo "${NAME}: no API key in Keychain service '\$_svc'." >&2
      echo "  add it once with: security add-generic-password -s '\$_svc' -a \"\$USER\" -w" >&2
      return 1
    fi
    CLAUDE_CONFIG_DIR="\$_cfg" ANTHROPIC_API_KEY="\$_key" "\$_bin" "\$@"
  else
    CLAUDE_CONFIG_DIR="\$_cfg" "\$_bin" "\$@"
  fi
}
BLOCK
  printf '%s\n' "$END_MARK"
} > "${RC}.cwnew"

# --- syntax-check before committing -----------------------------------------
if command -v "$CHECK_SHELL" >/dev/null 2>&1; then
  if ! "$CHECK_SHELL" -n "${RC}.cwnew" 2>/tmp/cw_rc_err; then
    echo "ERROR: resulting $RC would have a syntax error -- NOT applied." >&2
    sed 's/^/  /' /tmp/cw_rc_err >&2 || true
    rm -f "${RC}.cwtmp" "${RC}.cwnew" /tmp/cw_rc_err
    echo "Your $RC is unchanged (backup at $BAK)." >&2
    exit 1
  fi
fi
mv "${RC}.cwnew" "$RC"
rm -f "${RC}.cwtmp" /tmp/cw_rc_err 2>/dev/null || true

# --- key existence hint (no secret printed) ---------------------------------
KEY_NOTE=""
if [ -n "$KEYCHAIN_SVC" ]; then
  if security find-generic-password -s "$KEYCHAIN_SVC" >/dev/null 2>&1; then
    KEY_NOTE="Keychain item '$KEYCHAIN_SVC' found."
  else
    KEY_NOTE="Keychain item '$KEYCHAIN_SVC' NOT found yet -- add it once:
  security add-generic-password -s '$KEYCHAIN_SVC' -a \"\$USER\" -w
  (you'll be prompted to paste the work API key; it is not echoed)"
  fi
fi

cat <<DONE

Done. Added the '${NAME}' function to $RC (backup: $BAK).

Activate it:  source "$RC"   (or open a new terminal)
Verify:       type ${NAME}

Use it:
  ${NAME}                 # runs Claude Code with the isolated work profile
  ${NAME} --version       # any normal claude args pass through

Profile dir:  ${CONFIG_DIR}
$( [ -n "$KEYCHAIN_SVC" ] && echo "Work auth:    API key from Keychain ('$KEYCHAIN_SVC')." || echo "Work auth:    subscription -- run '${NAME}' then /login the first time." )
$( [ -n "$KEY_NOTE" ] && echo "$KEY_NOTE" )

Keychain caveat: macOS stores Claude *subscription* logins in the shared
Keychain, so two subscription accounts can't be active at once (switching
needs /logout + /login). For true side-by-side work+personal, use an API
key for the work side (--api-key-keychain), which this function supports.

Remove later: delete the marked block in $RC (between the '>>> ${NAME}' lines).
DONE
