#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
SKILL=$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // ""')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')

case "$SKILL" in
  *pr-create) NAME="pr-create" ;;
  *pr-update) NAME="pr-update" ;;
  *) exit 0 ;;
esac

# check-pr-command.sh がこのマーカーを見て gh pr create/edit の実行可否を判定する
MARKER_FILE="${TMPDIR:-/tmp}/claude-pr-skill-invoked-${SESSION_ID}"
grep -qxF "$NAME" "$MARKER_FILE" 2>/dev/null || printf '%s\n' "$NAME" >> "$MARKER_FILE"
