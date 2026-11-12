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
API_SUBCOMMAND='gh[[:space:]]+api\b'

find_invoked() {
  printf '%s\n' "$COMMAND" | grep -oE "${CMD_START}$1" 2>/dev/null | head -1 | grep -oE 'gh.*' 2>/dev/null || true
}

block_unless_claude_suffix() {
  local body="$1" matched="$2" example="$3"
  if [ -z "$body" ]; then
    return
  fi
  # PASS: 未解決のコマンド置換(実行時に本文が決まるため静的検証できない)
  case "$body" in
    '$('*) return ;;
  esac
  if printf '%s' "$body" | grep -qE '\(Claude\)[[:space:]]*$'; then
    return
  fi
  local reason="${matched} の本文末尾に \"(Claude)\" が含まれていません。

検出された本文: \"${body}\"

本文の末尾に \"(Claude)\" を追加してから再実行してください。
例: ${example}"
  printf '%s' "$reason" | jq -Rs '{decision: "block", reason: .}'
  exit 0
}

MATCHED=$(find_invoked "$TARGET_SUBCOMMAND")
# PASS: --body-file / -F はファイルから本文を読むため静的検証できない
if [ -n "$MATCHED" ] && ! printf '%s\n' "$COMMAND" | grep -qE '(--body-file|-F)\b'; then
  BODY=$(printf '%s' "$COMMAND" | \
    perl -0777 -ne '
      if (/(?:--body|-b)\s+'\''([^'\'']+)'\''/s)  { print $1; exit }
      if (/(?:--body|-b)\s+"((?:[^"\\]|\\.)*)"/s) { (my $m=$1)=~s/\\(.)/$1/g; print $m; exit }
      if (/(?:--body|-b)\s+'\''?"?([^'\''"\s]+)/s) { print $1; exit }
    ' 2>/dev/null || true)
  block_unless_claude_suffix "$BODY" "$MATCHED" "${MATCHED} 123 --body '対応しました (Claude)'"
fi

API_MATCHED=$(find_invoked "$API_SUBCOMMAND")
if [ -n "$API_MATCHED" ]; then
  # 'body=...' / "body=..." / body='...' / body="..." / body=... の順に探す。
  # -F / --field の値が @ で始まる場合はファイルから読むため静的検証できず、何も出力しない
  API_BODY=$(printf '%s' "$COMMAND" | \
    perl -0777 -ne '
      my $flag = qr/(?:^|\s)(-[fF]|--raw-field|--field)\s+/;
      my ($f, $v);
      if    (/${flag}\x27body=([^\x27]*)\x27/s)  { ($f, $v) = ($1, $2) }
      elsif (/${flag}"body=((?:[^"\\]|\\.)*)"/s) { ($f, $v) = ($1, $2); $v =~ s/\\(.)/$1/g }
      elsif (/${flag}body=\x27([^\x27]*)\x27/s)  { ($f, $v) = ($1, $2) }
      elsif (/${flag}body="((?:[^"\\]|\\.)*)"/s) { ($f, $v) = ($1, $2); $v =~ s/\\(.)/$1/g }
      elsif (/${flag}body=([^\s\x27"]+)/s)       { ($f, $v) = ($1, $2) }
      else  { exit }
      exit if $f =~ /^(?:-F|--field)$/ && $v =~ /^@/;
      print $v;
    ' 2>/dev/null || true)
  block_unless_claude_suffix "$API_BODY" "gh api" "gh api .../replies -f body='対応しました (Claude)'"
fi
