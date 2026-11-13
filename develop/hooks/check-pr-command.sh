#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')
AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // ""')

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
  block "${command_label} は、Skill ツールで develop:${skill_name} を起動し、その手順の中で実行してください。"
}

block_unless_pr_writer() {
  if [ "$AGENT_TYPE" != "develop:pr-writer" ]; then
    block "PR のタイトルと本文は develop:pr-writer が書き、pr-writer 自身が gh pr create / gh pr edit で反映します（develop:ship の「5. PR」）。メインエージェントは本文を書き直しません。直したい点は、同じ pr-writer に SendMessage で伝えて反映させてください。"
  fi
}

# 文字列中に "gh pr create" が含まれるだけの誤検知(コミットメッセージ等)を避けるため、
# 実際にコマンドとして起動される位置(行頭 / && / || / ; / | の直後)だけにマッチさせる
CMD_START='(^|&&|\|\||;|\|)[[:space:]]*'

if printf '%s\n' "$COMMAND" | grep -qE "${CMD_START}gh[[:space:]]+pr[[:space:]]+create\b"; then
  if ! skill_invoked "ship"; then
    block_use_skill "ship" "gh pr create"
  fi
  if ! skill_invoked "simplify"; then
    block "gh pr create の前に simplify スキルで差分をセルフレビューしてください（develop:ship）。"
  fi
  block_unless_pr_writer
  exit 0
fi

if printf '%s\n' "$COMMAND" | grep -qE "${CMD_START}gh[[:space:]]+pr[[:space:]]+edit\b"; then
  if ! skill_invoked "ship"; then
    block_use_skill "ship" "gh pr edit"
  fi
  if printf '%s\n' "$COMMAND" | grep -qE '(^|[[:space:]])((--title|--body|--body-file)([[:space:]=]|$)|-[tbF])'; then
    block_unless_pr_writer
  fi
  exit 0
fi

exit 0
