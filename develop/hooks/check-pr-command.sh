#!/usr/bin/env bash
# gh pr create / gh pr edit の直接実行をブロックし、対応する develop skill の起動を必須にする PreToolUse hook
set -euo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')

if [ -z "$COMMAND" ]; then
  exit 0
fi

if printf '%s\n' "$COMMAND" | grep -qE '\-\-help\b|(^|\s)-h(\s|$)'; then
  exit 0
fi

MARKER_FILE="${TMPDIR:-/tmp}/claude-pr-skill-invoked-${SESSION_ID}"

skill_invoked() {
  [ -f "$MARKER_FILE" ] && grep -qxF "$1" "$MARKER_FILE"
}

block() {
  local skill_name="$1"
  local command_label="$2"
  local reason
  reason="${command_label} を直接実行せず、先に Skill ツールで develop:${skill_name} を起動してください。

このコマンドは develop:${skill_name} skill の手順に沿って実行する必要があります。
Skill ツールで develop:${skill_name} を起動し、その手順の中で ${command_label} を実行してください。"
  printf '%s' "$reason" | jq -Rs '{decision: "block", reason: .}'
  exit 0
}

if printf '%s\n' "$COMMAND" | grep -qE '\bgh\s+pr\s+create\b'; then
  if ! skill_invoked "pr-create"; then
    block "pr-create" "gh pr create"
  fi
  exit 0
fi

if printf '%s\n' "$COMMAND" | grep -qE '\bgh\s+pr\s+edit\b'; then
  if ! skill_invoked "pr-update"; then
    block "pr-update" "gh pr edit"
  fi
  exit 0
fi

exit 0
