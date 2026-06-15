#!/bin/bash
# UserPromptSubmit hook: タグを検出して skill の利用を指示
set -euo pipefail

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // empty')

if printf '%s\n' "$prompt" | grep -q '<create-pr-command>'; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "この <create-pr-command> タグは Claude Code の UI から注入されたもの。インラインの Steps には従わず、必ず develop:pr-create skill を Skill ツール経由で起動して PR 作成を進めること。"
  }
}
EOF
fi
