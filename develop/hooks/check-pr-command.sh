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
  block "${command_label} は、Skill ツールで develop:${skill_name} を起動し、その手順の中で実行してください。"
}

block_unless_pr_writer() {
  local agent_type
  agent_type=$(printf '%s' "$INPUT" | jq -r '.agent_type // ""')
  if [ "$agent_type" != "develop:pr-writer" ]; then
    block "PR のタイトルと本文は develop:pr-writer が書き、pr-writer 自身が gh pr create / gh pr edit で反映します（develop:ship の「5. PR」）。メインエージェントは本文を書き直しません。直したい点は、同じ pr-writer に SendMessage で伝えて反映させてください。"
  fi
}

PR_BODY_MAX_CHARS=1500

body_file_char_count() {
  printf '%s' "$INPUT" | python3 -c '
import json, os, shlex, sys

data = json.load(sys.stdin)
lexer = shlex.shlex(data["tool_input"]["command"], posix=True, punctuation_chars=";&|")
lexer.whitespace_split = True
try:
    tokens = list(lexer)
except ValueError:
    sys.exit(0)

path = None
in_pr_command = False
for i, token in enumerate(tokens):
    if set(token) <= set(";&|"):
        in_pr_command = False
    elif i >= 2 and tokens[i - 2:i] == ["gh", "pr"] and token in ("create", "edit"):
        in_pr_command = True
    elif in_pr_command and token in ("--body-file", "-F") and i + 1 < len(tokens):
        path = tokens[i + 1]
    elif in_pr_command and token.startswith("--body-file="):
        path = token[len("--body-file="):]
    elif in_pr_command and token.startswith("-F") and len(token) > 2:
        path = token[2:].removeprefix("=")

if not path or path == "-":
    sys.exit(0)
path = os.path.join(data.get("cwd") or os.getcwd(), os.path.expanduser(path))
try:
    with open(path, encoding="utf-8") as body:
        print(len(body.read()))
except (OSError, UnicodeDecodeError):
    pass
'
}

block_if_body_too_long() {
  local char_count
  char_count=$(body_file_char_count || true)
  if [ -n "$char_count" ] && [ "$char_count" -gt "$PR_BODY_MAX_CHARS" ]; then
    block "PR 本文が ${char_count} 字で、上限の ${PR_BODY_MAX_CHARS} 字を超えています。差分を見れば分かること（変更したファイルや関数の列挙、コードの書き写し）や、CI の結果・実行したコマンドを削り、${PR_BODY_MAX_CHARS} 字以内にしてから反映し直してください。"
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
  block_if_body_too_long
  exit 0
fi

if printf '%s\n' "$COMMAND" | grep -qE "${CMD_START}gh[[:space:]]+pr[[:space:]]+edit\b"; then
  if ! skill_invoked "ship"; then
    block_use_skill "ship" "gh pr edit"
  fi
  PR_EDIT_ARGS=$(printf '%s\n' "$COMMAND" | grep -oE "${CMD_START}gh[[:space:]]+pr[[:space:]]+edit\b([^;&|]|&[^&;|])*" || true)
  if printf '%s\n' "$PR_EDIT_ARGS" | grep -qE '(^|[[:space:]])((--title|--body|--body-file)([[:space:]=]|$)|-[tbF])'; then
    block_unless_pr_writer
    block_if_body_too_long
  fi
  exit 0
fi

exit 0
