#!/usr/bin/env bash
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

# hook は都度別プロセスで起動されるため、skill 起動済みかどうかの状態はファイルで受け渡す
MARKER_FILE="${TMPDIR:-/tmp}/claude-pr-skill-invoked-${SESSION_ID}"

skill_invoked() {
  [ -f "$MARKER_FILE" ] && grep -qxF "$1" "$MARKER_FILE"
}

block() {
  local reason="$1"
  printf '%s' "$reason" | jq -Rs '{decision: "block", reason: .}'
  exit 0
}

block_use_skill() {
  local skill_name="$1"
  local command_label="$2"
  block "${command_label} を直接実行せず、Skill ツールで develop:${skill_name} を起動し、その手順の中で実行してください。"
}

# 文字列中に "gh pr create" が含まれるだけの誤検知(コミットメッセージ等)を避けるため、
# 実際にコマンドとして起動される位置(行頭 / && / || / ; / | の直後)だけにマッチさせる
CMD_START='(^|&&|\|\||;|\|)[[:space:]]*'

if printf '%s\n' "$COMMAND" | grep -qE "${CMD_START}gh[[:space:]]+pr[[:space:]]+create\b"; then
  if ! skill_invoked "pr-create"; then
    block_use_skill "pr-create" "gh pr create"
  fi
  if ! skill_invoked "simplify"; then
    block "gh pr create の前に simplify スキルで差分をセルフレビューしてください（develop:pr-create の作成手順 手順3）。"
  fi
  exit 0
fi

if printf '%s\n' "$COMMAND" | grep -qE "${CMD_START}gh[[:space:]]+pr[[:space:]]+edit\b"; then
  if ! skill_invoked "pr-update"; then
    block_use_skill "pr-update" "gh pr edit"
  fi
  exit 0
fi

exit 0
