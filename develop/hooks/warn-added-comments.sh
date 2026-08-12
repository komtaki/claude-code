#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')

case "$file" in
*.md | *.markdown | *.txt | *.mdx) exit 0 ;;
esac

count_comments() {
  grep -cE '^[[:space:]]*(#|//|/\*|\*)' <<<"$1" 2>/dev/null || true
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
  msg="⚠️ コメントを ${added} 行追加しました。理由・経緯・ハマりどころはコードでなく PR/commit に書くルールです(no-rationale-comments)。不要なコメントなら削除してください。"
  jq -n --arg m "$msg" '{systemMessage:$m, hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$m}}'
fi
exit 0
