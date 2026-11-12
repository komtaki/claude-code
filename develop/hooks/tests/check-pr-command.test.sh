#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hook="$script_dir/../check-pr-command.sh"
mark="$script_dir/../mark-pr-skill-invoked.sh"

failures=0
test_counter=0

marker_file_for() {
  printf '%s' "${TMPDIR:-/tmp}/claude-pr-skill-invoked-$1"
}

run_hook() {
  local cmd="$1" session="$2"
  jq -n --arg cmd "$cmd" --arg session "$session" \
    '{tool_input:{command:$cmd}, session_id:$session}' | bash "$hook"
}

run_mark() {
  local skill="$1" session="$2"
  jq -n --arg skill "$skill" --arg session "$session" \
    '{tool_input:{skill:$skill}, session_id:$session}' | bash "$mark"
}

new_session() {
  test_counter=$((test_counter + 1))
  printf 'check-pr-command-test-%s-%s' "$$" "$test_counter"
}

mark_invoked() {
  local session="$1" skill="$2"
  printf '%s\n' "$skill" >> "$(marker_file_for "$session")"
}

assert_pass() {
  local desc="$1" out="$2"
  if [ -z "$out" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (expected no block, got [$out])"
    failures=$((failures + 1))
  fi
}

assert_block_contains() {
  local desc="$1" out="$2" needle="$3" decision reason
  decision=$(printf '%s' "$out" | jq -r '.decision // empty')
  reason=$(printf '%s' "$out" | jq -r '.reason // empty')
  if [ "$decision" = "block" ] && printf '%s' "$reason" | grep -qF "$needle"; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (decision=[$decision] reason=[$reason])"
    failures=$((failures + 1))
  fi
}

session=$(new_session)
out=$(run_hook 'gh pr create --title "x" --body "y"' "$session")
assert_block_contains "gh pr create with no skills invoked blocks on ship" "$out" "develop:ship"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
mark_invoked "$session" "pr-create"
mark_invoked "$session" "simplify"
out=$(run_hook 'gh pr create --title "x" --body "y"' "$session")
assert_block_contains "gh pr create with only the removed pr-create marker blocks on ship" "$out" "develop:ship"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
mark_invoked "$session" "ship"
out=$(run_hook 'gh pr create --title "x" --body "y"' "$session")
assert_block_contains "gh pr create without simplify blocks on simplify" "$out" "simplify"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
mark_invoked "$session" "ship"
mark_invoked "$session" "simplify"
out=$(run_hook 'gh pr create --title "x" --body "y"' "$session")
assert_pass "gh pr create with ship and simplify invoked passes" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
run_mark "develop:ship" "$session"
run_mark "simplify" "$session"
out=$(run_hook 'gh pr create --title "x" --body "y"' "$session")
assert_pass "skills recorded by mark-pr-skill-invoked unlock gh pr create" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
run_mark "develop:relationship" "$session"
run_mark "simplify" "$session"
out=$(run_hook 'gh pr create --title "x" --body "y"' "$session")
assert_block_contains "skill names merely ending in ship are not recorded as ship" "$out" "develop:ship"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
out=$(run_hook 'gh pr edit 1 --title "x"' "$session")
assert_block_contains "gh pr edit without pr-update blocks" "$out" "develop:pr-update"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
mark_invoked "$session" "pr-update"
out=$(run_hook 'gh pr edit 1 --title "x"' "$session")
assert_pass "gh pr edit with pr-update invoked passes" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
out=$(run_hook 'gh pr view 1' "$session")
assert_pass "gh pr view is not gated" "$out"

session=$(new_session)
out=$(run_hook 'git commit -m "fix: gh pr create の挙動を修正"' "$session")
assert_pass "gh pr create mentioned mid-string is not gated" "$out"

if [ "$failures" -gt 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "All tests passed"
