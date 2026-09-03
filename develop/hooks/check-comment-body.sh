#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')

if [ -z "$COMMAND" ]; then
  exit 0
fi

# 文字列中に "gh issue comment" 等が含まれるだけの誤検知(コミットメッセージ等)を避けるため、
# 実際にコマンドとして起動される位置(行頭 / && / || / ; / | の直後)だけにマッチさせる
CMD_START='(^|&&|\|\||;|\|)[[:space:]]*'
TARGET_SUBCOMMAND='gh[[:space:]]+(issue[[:space:]]+comment|pr[[:space:]]+comment|pr[[:space:]]+review)\b'

MATCHED=$(printf '%s\n' "$COMMAND" | grep -oE "${CMD_START}${TARGET_SUBCOMMAND}" 2>/dev/null | head -1 | grep -oE 'gh.*' 2>/dev/null || true)
if [ -z "$MATCHED" ]; then
  exit 0
fi

# PASS: --body-file / -F はファイルから本文を読むため静的検証できない
if printf '%s\n' "$COMMAND" | grep -qE '(--body-file|-F)\b'; then
  exit 0
fi

BODY=$(printf '%s' "$COMMAND" | \
  perl -0777 -ne '
    if (/(?:--body|-b)\s+'\''([^'\'']+)'\''/s)  { print $1; exit }
    if (/(?:--body|-b)\s+"((?:[^"\\]|\\.)*)"/s) { (my $m=$1)=~s/\\(.)/$1/g; print $m; exit }
    if (/(?:--body|-b)\s+'\''?"?([^'\''"\s]+)/s) { print $1; exit }
  ' 2>/dev/null || true)

if [ -z "$BODY" ]; then
  exit 0
fi

# PASS: 未解決のコマンド置換(実行時に本文が決まるため静的検証できない)
case "$BODY" in
  '$('*) exit 0 ;;
esac

if printf '%s' "$BODY" | grep -qE '\(Claude\)[[:space:]]*$'; then
  exit 0
fi

REASON="${MATCHED} の本文末尾に \"(Claude)\" が含まれていません。

検出された本文: \"${BODY}\"

本文の末尾に \"(Claude)\" を追加してから再実行してください。
例: ${MATCHED} 123 --body '対応しました (Claude)'"

printf '%s' "$REASON" | jq -Rs '{decision: "block", reason: .}'
