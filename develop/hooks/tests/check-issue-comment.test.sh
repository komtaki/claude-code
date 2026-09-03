#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hook="$script_dir/../check-issue-comment.sh"

failures=0

run_hook() {
  jq -n --arg cmd "$1" '{tool_name:"Bash", tool_input:{command:$cmd}}' | bash "$hook"
}

assert_pass() {
  local desc="$1" cmd="$2" out
  out=$(run_hook "$cmd")
  if [ -z "$out" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (expected no block, got [$out])"
    failures=$((failures + 1))
  fi
}

assert_block() {
  local desc="$1" cmd="$2" decision
  decision=$(run_hook "$cmd" | jq -r '.decision // empty')
  if [ "$decision" = "block" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (expected block, got decision=[$decision])"
    failures=$((failures + 1))
  fi
}

assert_pass "double quote body ending with (Claude)" \
  'gh issue comment 123 --body "対応しました (Claude)"'

assert_pass "single quote body ending with (Claude)" \
  "gh issue comment 123 --body '対応しました (Claude)'"

assert_pass "-b short flag ending with (Claude)" \
  'gh issue comment 123 -b "done (Claude)"'

assert_pass "trailing whitespace after (Claude) still passes" \
  'gh issue comment 123 --body "対応しました (Claude) "'

assert_block "body missing (Claude) suffix" \
  'gh issue comment 123 --body "対応しました"'

assert_block "(Claude) present but not at the end" \
  'gh issue comment 123 --body "(Claude) 対応しました"'

assert_pass "non-comment gh subcommand is ignored" \
  'gh issue view 123'

assert_pass "gh issue comment mentioned mid-string is not treated as the command" \
  'git commit -m "fix: gh issue comment 123 の挙動を修正"'

assert_pass "--body-file cannot be validated statically" \
  'gh issue comment 123 --body-file notes.txt'

assert_pass "unresolved command substitution cannot be validated statically" \
  'gh issue comment 123 --body "$(build-comment)"'

if [ "$failures" -gt 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "All tests passed"
