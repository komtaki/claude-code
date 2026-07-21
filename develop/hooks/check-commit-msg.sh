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

# PASS: no git commit found in command
if ! printf '%s\n' "$COMMAND" | grep -qE '\bgit\s+commit\b'; then
  exit 0
fi

# Extract the -m / --message value via perl (handles single/double quotes and
# escaped chars). Run against the whole command rather than a single line so
# multi-line messages are not truncated: the quoted-string regexes use /s and a
# negated character class, so they span newlines and stop at the real closing
# quote (e.g. before a trailing `&& git log`). The unquoted fallback tolerates a
# stray leading quote so an unterminated quote on the first line is not mistaken
# for part of the message (e.g. "'feat:").
#
# The first regex handles the heredoc command-substitution form that Claude
# commonly emits, e.g. `-m "$(cat <<'EOF' ... EOF)"`. Without it the quoted
# regexes would capture the literal `$(cat <<'EOF'` as the message and block a
# valid commit. It matches the opening `<<[-]DELIM` (delimiter optionally quoted)
# and captures the heredoc body up to the closing delimiter line.
MSG=$(printf '%s' "$COMMAND" | \
  perl -0777 -ne '
    if (/(?:-m|--message)\s+"?\$\(\s*cat\s*<<-?\s*["'\'']?(\w+)["'\'']?\r?\n(.*?)\r?\n[ \t]*\1\b/s) { print $2; exit }
    if (/(?:-m|--message)\s+'\''([^'\'']+)'\''/s)  { print $1; exit }
    if (/(?:-m|--message)\s+"((?:[^"\\]|\\.)*)"/s) { (my $m=$1)=~s/\\(.)/$1/g; print $m; exit }
    if (/(?:-m|--message)\s+'\''?"?([^'\''"\s]+)/s) { print $1; exit }
  ' 2>/dev/null || true)

# PASS: no -m flag found (e.g. using -F, --file, or interactive editor)
if [ -z "$MSG" ]; then
  exit 0
fi

# PASS: message is an unresolved command substitution (e.g. `-m "$(build-msg)"`).
# The real message is produced at runtime, so it cannot be validated statically;
# blocking on the literal `$(...)` text would be a false positive.
case "$MSG" in
  '$('*) exit 0 ;;
esac

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
