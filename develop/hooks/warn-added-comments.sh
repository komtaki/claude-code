#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')

case "$file" in
*.md | *.markdown | *.txt | *.mdx) exit 0 ;;
esac

count_comments() {
  local text="$1"
  local hash_re='^[[:space:]]*(#|//|/\*|\*)'
  local dq='"""'
  local tq="'''"
  local open_re="^[[:space:]]*($dq|$tq)"
  local count=0 in_doc=0 delim="" line after
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_doc" -eq 1 ]; then
      count=$((count + 1))
      case "$line" in
      *"$delim"*) in_doc=0 ;;
      esac
      continue
    fi
    if [[ "$line" =~ $hash_re ]]; then
      count=$((count + 1))
      continue
    fi
    if [[ "$line" =~ $open_re ]]; then
      count=$((count + 1))
      case "$line" in
      *"$dq"*) delim="$dq" ;;
      *) delim="$tq" ;;
      esac
      after="${line#*"$delim"}"
      case "$after" in
      *"$delim"*) ;;
      *) in_doc=1 ;;
      esac
    fi
  done <<<"$text"
  printf '%s\n' "$count"
}

added=0
if [ "$tool" = "Edit" ]; then
  old=$(printf '%s' "$input" | jq -r '.tool_input.old_string // ""')
  new=$(printf '%s' "$input" | jq -r '.tool_input.new_string // ""')
  added=$(($(count_comments "$new") - $(count_comments "$old")))
elif [ "$tool" = "Write" ]; then
  content=$(printf '%s' "$input" | jq -r '.tool_input.content // ""')
  added=$(count_comments "$content")
fi

if [ "${added:-0}" -gt 0 ]; then
  msg="コメント${added}行追加。書くのはコードで分からないWhyのみ(non-redundant-comment)。経緯・詰まった点はPR/commitへ、不要なら削除。"
  jq -n --arg m "$msg" '{systemMessage:$m, hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$m}}'
fi
exit 0
