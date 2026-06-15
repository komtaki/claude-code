#!/bin/bash
# PostToolUse hook: ファイル保存後に末尾空白除去と末尾改行付与を行う
set -euo pipefail

FILE=$(jq -r '.tool_input.file_path // empty')

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  exit 0
fi

# 末尾空白を除去（GNU sed / BSD sed 両対応）
if sed --version 2>/dev/null | grep -q GNU; then
  sed -i 's/[[:space:]]*$//' "$FILE"
else
  sed -i '' 's/[[:space:]]*$//' "$FILE"
fi

# 末尾改行がなければ付与
if [ -s "$FILE" ] && [ "$(tail -c1 "$FILE" | wc -l)" -eq 0 ]; then
  printf '\n' >> "$FILE"
fi
