#!/usr/bin/env bash
# PreToolUse hook (matcher: Skill): develop:pr-create/pr-update の起動をセッションごとのマーカーファイルに記録する
set -euo pipefail

INPUT=$(cat)
SKILL=$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // ""')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')

case "$SKILL" in
  *pr-create) NAME="pr-create" ;;
  *pr-update) NAME="pr-update" ;;
  *) exit 0 ;;
esac

MARKER_FILE="${TMPDIR:-/tmp}/claude-pr-skill-invoked-${SESSION_ID}"
grep -qxF "$NAME" "$MARKER_FILE" 2>/dev/null || printf '%s\n' "$NAME" >> "$MARKER_FILE"
