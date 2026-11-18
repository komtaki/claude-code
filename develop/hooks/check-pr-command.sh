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

block_unless_pr_writer() {
  local agent_type
  agent_type=$(printf '%s' "$INPUT" | jq -r '.agent_type // ""')
  if [ "$agent_type" != "develop:pr-writer" ]; then
    block "PR のタイトルと本文は develop:pr-writer が書き、pr-writer 自身が gh pr create / gh pr edit で反映します（develop:ship の「5. PR」）。メインエージェントは本文を書き直しません。直したい点は、同じ pr-writer に SendMessage で伝えて反映させてください。"
  fi
}

PR_BODY_MAX_CHARS=1500

parse_pr_command() {
  printf '%s' "$INPUT" | python3 -c '
import json, os, shlex, sys

data = json.load(sys.stdin)
command = data["tool_input"]["command"].replace("\\\n", "").replace("\n", ";")
lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|")
lexer.whitespace_split = True
try:
    tokens = list(lexer)
except ValueError:
    print("body=unparsable")
    sys.exit(0)

path = None
inline_body = False
has_cd = False
pr_subcommand = None
draft = False
for i, token in enumerate(tokens):
    if set(token) <= set(";&|"):
        pr_subcommand = None
    elif token == "cd" and (i == 0 or set(tokens[i - 1]) <= set(";&|")):
        has_cd = True
    elif i >= 2 and tokens[i - 2:i] == ["gh", "pr"] and token in ("create", "edit"):
        pr_subcommand = token
    elif pr_subcommand is None:
        continue
    elif pr_subcommand == "create" and token in ("--draft", "--draft=true", "-d"):
        draft = True
    elif token in ("--body-file", "-F") and i + 1 < len(tokens):
        path = tokens[i + 1]
    elif token.startswith("--body-file="):
        path = token[len("--body-file="):]
    elif token.startswith("-F") and len(token) > 2:
        path = token[2:].removeprefix("=")
    elif token == "--body" or token.startswith("--body=") or (token.startswith("-b") and not token.startswith("--")):
        inline_body = True

def body_result(path):
    if inline_body or path == "-":
        return "inline"
    if not path:
        return ""
    path = os.path.expanduser(os.path.expandvars(path))
    if has_cd and not os.path.isabs(path):
        return f"relative_after_cd {path}"
    path = os.path.join(data.get("cwd") or os.getcwd(), path)
    try:
        with open(path, encoding="utf-8") as body:
            return f"count {len(body.read())}"
    except FileNotFoundError:
        return f"missing {path}"
    except (OSError, UnicodeDecodeError):
        return ""

print(f"body={body_result(path)}")
if draft:
    print("draft=1")
'
}

block_if_body_too_long() {
  local result kind value
  result=$(printf '%s\n' "$1" | sed -n 's/^body=//p')
  kind="${result%% *}"
  value="${result#* }"
  if [ "$kind" = "unparsable" ]; then
    block "コマンドを解析できないため、PR 本文の字数を確かめられません。本文はファイルに書き、--body-file に絶対パスで渡して反映し直してください。"
  fi
  if [ "$kind" = "inline" ]; then
    block "PR 本文は、ファイルに書いて --body-file に絶対パスで渡してください。--body・-b・--body-file - では字数を確かめられません。"
  fi
  if [ "$kind" = "relative_after_cd" ]; then
    block "コマンド中に cd があるため、相対パスの本文ファイル ${value} がどこを指すか確かめられません。--body-file に絶対パスで渡し直してください。"
  fi
  if [ "$kind" = "missing" ]; then
    block "PR 本文のファイル ${value} が見つからないため、字数を確かめられません。絶対パスで渡し直してください。"
  fi
  if [ "$kind" = "count" ] && [ "$value" -gt "$PR_BODY_MAX_CHARS" ]; then
    block "PR 本文が ${value} 字で、上限の ${PR_BODY_MAX_CHARS} 字を超えています。差分を見れば分かること（変更したファイルや関数の列挙、コードの書き写し）や、CI の結果・実行したコマンドを削り、${PR_BODY_MAX_CHARS} 字以内にしてから反映し直してください。"
  fi
}

# 文字列中に "gh pr create" が含まれるだけの誤検知(コミットメッセージ等)を避けるため、
# 実際にコマンドとして起動される位置(行頭 / && / || / ; / | の直後)だけにマッチさせる
CMD_START='(^|&&|\|\||;|\|)[[:space:]]*'

if printf '%s\n' "$COMMAND" | grep -qE "${CMD_START}gh[[:space:]]+pr[[:space:]]+create\b"; then
  if ! skill_invoked "simplify"; then
    block "gh pr create の前に simplify スキルで差分をセルフレビューしてください（develop:ship）。"
  fi
  block_unless_pr_writer
  PR_COMMAND=$(parse_pr_command || true)
  block_if_body_too_long "$PR_COMMAND"
  if ! printf '%s\n' "$PR_COMMAND" | grep -qx draft=1; then
    block "PR は draft で作ってください（gh pr create --draft）。"
  fi
  exit 0
fi

if printf '%s\n' "$COMMAND" | grep -qE "${CMD_START}gh[[:space:]]+pr[[:space:]]+edit\b"; then
  PR_EDIT_ARGS=$(printf '%s\n' "$COMMAND" | grep -oE "${CMD_START}gh[[:space:]]+pr[[:space:]]+edit\b([^;&|]|&[^&;|])*" || true)
  if printf '%s\n' "$PR_EDIT_ARGS" | grep -qE '(^|[[:space:]])((--title|--body|--body-file)([[:space:]=]|$)|-[tbF])'; then
    block_unless_pr_writer
    if printf '%s\n' "$PR_EDIT_ARGS" | grep -qE '(^|[[:space:]])((--body|--body-file)([[:space:]=]|$)|-[bF])'; then
      block_if_body_too_long "$(parse_pr_command || true)"
    fi
  fi
  exit 0
fi

exit 0
