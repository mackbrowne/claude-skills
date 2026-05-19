#!/usr/bin/env bash
# Package every skill under skills/ into dist/<name>.skill (a plain zip of the
# skill folder). Re-runnable; overwrites existing packages.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/dist"
cd "$ROOT/skills"

found=0
for d in */; do
  name="${d%/}"
  [ -f "$name/SKILL.md" ] || { echo "skip $name (no SKILL.md)"; continue; }
  found=1
  rm -f "$ROOT/dist/$name.skill"
  zip -r -q -X "$ROOT/dist/$name.skill" "$name" \
    -x '*.DS_Store' -x '*/.git/*' -x '*.bak*'
  echo "packaged dist/$name.skill"
done
[ "$found" = 1 ] || { echo "no skills found" >&2; exit 1; }
