#!/usr/bin/env bash
# Conventional commit format validator for Claude Code PreToolUse hook.
# Reads hook JSON from stdin, extracts the git commit -m message, and
# blocks commits that don't follow the project convention.
#
# stdout JSON with decision:block → block with reason shown to Claude
# exit 0 with no output          → pass

set -euo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')

# PASS: empty command
if [ -z "$COMMAND" ]; then
  exit 0
fi

# PASS: gh commands are always allowed
if printf '%s\n' "$COMMAND" | grep -qE '^\s*gh\b'; then
  exit 0
fi

# Split compound commands on &&, ;, | and find the first git commit segment.
# Add trailing newline so `read` captures the last segment correctly.
GIT_COMMIT_CMD=""
while IFS= read -r segment; do
  trimmed=$(printf '%s' "$segment" | sed 's/^[[:space:]]*//')
  if printf '%s\n' "$trimmed" | grep -qE '^git\s+commit\b'; then
    GIT_COMMIT_CMD="$trimmed"
    break
  fi
done < <(printf '%s\n' "$COMMAND" | sed 's/&&/\n/g; s/;/\n/g; s/|/\n/g')

# PASS: no git commit found in command
if [ -z "$GIT_COMMIT_CMD" ]; then
  exit 0
fi

# Extract the -m / --message value via perl (handles single/double quotes and escaped chars).
MSG=$(printf '%s' "$GIT_COMMIT_CMD" | \
  perl -0777 -ne '
    if (/(?:-m|--message)\s+'\''([^'\'']+)'\''/s)  { print $1; exit }
    if (/(?:-m|--message)\s+"((?:[^"\\]|\\.)*)"/s) { (my $m=$1)=~s/\\(.)/$1/g; print $m; exit }
    if (/(?:-m|--message)\s+(\S+)/s)               { print $1; exit }
  ' 2>/dev/null || true)

# PASS: no -m flag found (e.g. using -F, --file, or interactive editor)
if [ -z "$MSG" ]; then
  exit 0
fi

# Validate only the first line of the message
FIRST_LINE=$(printf '%s' "$MSG" | head -n1)

VALID_TYPES="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"
CC_PATTERN="^(${VALID_TYPES})(\([^)]+\))?!?: .+"
FIXUP_PATTERN="^fixup! .+"

if printf '%s\n' "$FIRST_LINE" | grep -qE "$CC_PATTERN"; then
  exit 0
fi

if printf '%s\n' "$FIRST_LINE" | grep -qE "$FIXUP_PATTERN"; then
  exit 0
fi

# BLOCK: format violation
REASON="コミットメッセージが conventional commit フォーマットに従っていません。

検出されたメッセージ: \"${FIRST_LINE}\"

正しいフォーマット:
  <type>: <説明>

有効な type: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert

例:
  feat: ユーザープロフィールページを追加
  fix: ログイン時のメモリリークを修正
  docs: APIドキュメントを更新
  fixup! feat: ユーザープロフィールページを追加"

printf '%s' "$REASON" | jq -Rs '{decision: "block", reason: .}'
