#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hook="$script_dir/../session-start-skill-check.sh"

failures=0

out=$(echo '{}' | bash "$hook" 2>&1 || true)

if echo "$out" | jq -e . >/dev/null 2>&1; then
  echo "PASS: output is valid JSON"
else
  echo "FAIL: output is not valid JSON [$out]"
  failures=$((failures + 1))
fi

event=$(echo "$out" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null || true)
if [ "$event" = "SessionStart" ]; then
  echo "PASS: hookEventName is SessionStart"
else
  echo "FAIL: hookEventName=[$event]"
  failures=$((failures + 1))
fi

context=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)
for keyword in "Skill ツール" "develop:ship"; do
  if [[ "$context" == *"$keyword"* ]]; then
    echo "PASS: additionalContext mentions $keyword"
  else
    echo "FAIL: additionalContext does not mention $keyword"
    failures=$((failures + 1))
  fi
done

[ "$failures" -eq 0 ] || exit 1
