#!/usr/bin/env bash
# install.sh — installs the /sweep skill into ~/.claude/skills/
set -euo pipefail

DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
SKILL_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/skills/sweep" && pwd)"

if [ ! -d "$SKILL_SRC" ]; then
  echo "Error: skills/sweep not found relative to this script." >&2
  exit 1
fi

mkdir -p "$DEST"
cp -r "$SKILL_SRC" "$DEST/sweep"
echo "Installed: $DEST/sweep"
echo "The /sweep skill is ready. Start a new Claude Code conversation to use it."
