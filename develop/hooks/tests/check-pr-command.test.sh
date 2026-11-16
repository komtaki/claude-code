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
  local cmd="$1" session="$2" agent_type="${3:-}" cwd="${4:-}"
  jq -n --arg cmd "$cmd" --arg session "$session" --arg at "$agent_type" --arg cwd "$cwd" \
    '{tool_input:{command:$cmd}, session_id:$session} + (if $at == "" then {} else {agent_type:$at} end) + (if $cwd == "" then {} else {cwd:$cwd} end)' | bash "$hook"
}

export TMPDIR="${TMPDIR:-/tmp}"
body_dir=$(mktemp -d "$TMPDIR/check-pr-command-test.XXXXXX")
body_dir_name="${body_dir##*/}"
trap 'rm -rf "$body_dir"' EXIT

write_body() {
  local path="$1" char="$2" count="$3"
  python3 -c 'import sys; open(sys.argv[1], "w", encoding="utf-8").write(sys.argv[2] * int(sys.argv[3]))' "$path" "$char" "$count"
}

write_body "$body_dir/ascii-1500.md" a 1500
write_body "$body_dir/ascii-1501.md" a 1501
write_body "$body_dir/ja-1500.md" あ 1500
write_body "$body_dir/ja-1501.md" あ 1501

new_ready_session() {
  local session
  session=$(new_session)
  mark_invoked "$session" "simplify"
  printf '%s' "$session"
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
  if [ "$decision" = "block" ] && printf '%s' "$reason" | grep -qF -- "$needle"; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (decision=[$decision] reason=[$reason])"
    failures=$((failures + 1))
  fi
}

session=$(new_session)
out=$(run_hook "gh pr create --title x --body-file $body_dir/ascii-1500.md" "$session" "develop:pr-writer")
assert_block_contains "gh pr create with no skills invoked blocks on simplify" "$out" "simplify"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
out=$(run_hook "gh pr create --title x --body-file $body_dir/ascii-1500.md" "$session")
assert_block_contains "gh pr create from the main agent without simplify blocks on simplify" "$out" "simplify"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
mark_invoked "$session" "simplify"
out=$(run_hook "gh pr create --title x --body-file $body_dir/ascii-1500.md" "$session" "develop:pr-writer")
assert_pass "gh pr create from pr-writer with simplify invoked passes without ship" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
run_mark "simplify" "$session"
out=$(run_hook "gh pr create --title x --body-file $body_dir/ascii-1500.md" "$session" "develop:pr-writer")
assert_pass "simplify recorded by mark-pr-skill-invoked unlocks gh pr create" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
run_mark "develop:ship" "$session"
if [ -f "$(marker_file_for "$session")" ]; then
  echo "FAIL: mark-pr-skill-invoked does not record ship (marker=[$(cat "$(marker_file_for "$session")")])"
  failures=$((failures + 1))
else
  echo "PASS: mark-pr-skill-invoked does not record ship"
fi
rm -f "$(marker_file_for "$session")"

session=$(new_session)
out=$(run_hook 'gh pr edit 1 --title "x"' "$session" "develop:pr-writer")
assert_pass "gh pr edit --title from pr-writer passes without ship" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
mark_invoked "$session" "simplify"
out=$(run_hook 'gh pr create --title "x" --body "y"' "$session")
assert_block_contains "gh pr create from the main agent blocks on pr-writer" "$out" "develop:pr-writer"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
mark_invoked "$session" "simplify"
out=$(run_hook 'gh pr create --title "x" --body "y"' "$session" "general-purpose")
assert_block_contains "gh pr create from another subagent blocks on pr-writer" "$out" "develop:pr-writer"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
out=$(run_hook 'gh pr edit 1 --body-file body.md' "$session")
assert_block_contains "gh pr edit --body-file from the main agent blocks on pr-writer" "$out" "develop:pr-writer"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
out=$(run_hook 'gh pr edit 1 -F=body.md' "$session")
assert_block_contains "gh pr edit -F=file from the main agent blocks on pr-writer" "$out" "develop:pr-writer"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
out=$(run_hook 'gh pr edit 1 --title "x"' "$session")
assert_block_contains "gh pr edit --title from the main agent blocks on pr-writer" "$out" "develop:pr-writer"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
out=$(run_hook "gh pr edit 1 --body-file $body_dir/ascii-1500.md" "$session" "develop:pr-writer")
assert_pass "gh pr edit --body-file from pr-writer passes" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
out=$(run_hook 'gh pr edit 1 --add-label bug' "$session")
assert_pass "gh pr edit --add-label from the main agent passes" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
out=$(run_hook 'gh pr edit 1 -Fbody.md' "$session")
assert_block_contains "gh pr edit -Ffile from the main agent blocks on pr-writer" "$out" "develop:pr-writer"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
out=$(run_hook 'gh pr edit 1 -t"x"' "$session")
assert_block_contains "gh pr edit -t\"x\" from the main agent blocks on pr-writer" "$out" "develop:pr-writer"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
out=$(run_hook "gh pr edit 1 -F$body_dir/ascii-1500.md" "$session" "develop:pr-writer")
assert_pass "gh pr edit -Ffile from pr-writer passes" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
out=$(run_hook 'gh pr edit 1 --base main --fill' "$session")
assert_pass "gh pr edit with long flags starting with b or f from the main agent passes" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_session)
out=$(run_hook 'gh pr edit 1 --add-label x && grep -F y z' "$session")
assert_pass "short flags in commands chained after gh pr edit are not checked" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr create --title x --body-file $body_dir/ascii-1500.md" "$session" "develop:pr-writer")
assert_pass "gh pr create --body-file with exactly 1500 chars passes" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr create --title x --body-file $body_dir/ascii-1501.md" "$session" "develop:pr-writer")
assert_block_contains "gh pr create --body-file with 1501 chars blocks" "$out" "1501 字"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr create --title x --body-file $body_dir/ja-1500.md" "$session" "develop:pr-writer")
assert_pass "1500 Japanese chars are counted as chars, not bytes" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr create --title x --body-file $body_dir/ja-1501.md" "$session" "develop:pr-writer")
assert_block_contains "1501 Japanese chars block with the char count" "$out" "1501 字"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr create --title x -F $body_dir/ascii-1501.md" "$session" "develop:pr-writer")
assert_block_contains "gh pr create -F file with 1501 chars blocks" "$out" "1501 字"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr create --title x --body-file=$body_dir/ascii-1501.md" "$session" "develop:pr-writer")
assert_block_contains "gh pr create --body-file=file with 1501 chars blocks" "$out" "1501 字"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr edit 1 --body-file $body_dir/ascii-1501.md" "$session" "develop:pr-writer")
assert_block_contains "gh pr edit --body-file with 1501 chars blocks" "$out" "1501 字"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr edit 1 --body-file $body_dir/ascii-1500.md" "$session" "develop:pr-writer")
assert_pass "gh pr edit --body-file with exactly 1500 chars passes" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr create --title x --body-file ascii-1501.md" "$session" "develop:pr-writer" "$body_dir")
assert_block_contains "relative --body-file is resolved from cwd" "$out" "1501 字"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr create --title x --body-file $body_dir/missing.md" "$session" "develop:pr-writer")
assert_block_contains "missing --body-file blocks" "$out" "見つからない"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr create --title x --body-file \"\$TMPDIR/$body_dir_name/ascii-1501.md\"" "$session" "develop:pr-writer")
assert_block_contains "--body-file with \$TMPDIR and 1501 chars blocks" "$out" "1501 字"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr create --title x --body-file \"\$TMPDIR/$body_dir_name/ascii-1500.md\"" "$session" "develop:pr-writer")
assert_pass "--body-file with \$TMPDIR and 1500 chars passes" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr edit 1 --body-file \${TMPDIR}/$body_dir_name/ascii-1501.md" "$session" "develop:pr-writer")
assert_block_contains "--body-file with \${TMPDIR} and 1501 chars blocks" "$out" "1501 字"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr edit 1 --body-file \${TMPDIR}/$body_dir_name/ascii-1500.md" "$session" "develop:pr-writer")
assert_pass "--body-file with \${TMPDIR} and 1500 chars passes" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr create --title x --body-file -" "$session" "develop:pr-writer")
assert_block_contains "--body-file - (stdin) blocks" "$out" "--body-file"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr create --title x --body-file $body_dir/ascii-1500.md"$'\n'"grep -F $body_dir/ascii-1501.md foo" "$session" "develop:pr-writer")
assert_pass "-F on the next line is not counted as the body file" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr create --title x \\"$'\n'"  --body-file $body_dir/ascii-1501.md" "$session" "develop:pr-writer")
assert_block_contains "--body-file after a line continuation is still checked" "$out" "1501 字"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "cd $body_dir && gh pr create --title x --body-file ascii-1500.md" "$session" "develop:pr-writer" "$body_dir")
assert_block_contains "relative --body-file after cd blocks" "$out" "絶対パス"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "cd $body_dir"$'\n'"gh pr edit 1 --body-file ascii-1500.md" "$session" "develop:pr-writer" "$body_dir")
assert_block_contains "relative --body-file after cd on a previous line blocks" "$out" "絶対パス"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "cd $body_dir && gh pr create --title x --body-file $body_dir/ascii-1500.md" "$session" "develop:pr-writer")
assert_pass "absolute --body-file after cd passes" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook 'gh pr create --title x --body "y"' "$session" "develop:pr-writer")
assert_block_contains "gh pr create --body from pr-writer blocks" "$out" "--body-file"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook 'gh pr edit 1 -b "y"' "$session" "develop:pr-writer")
assert_block_contains "gh pr edit -b from pr-writer blocks" "$out" "--body-file"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "cat $body_dir/ascii-1501.md | gh pr create --title x --body-file -" "$session" "develop:pr-writer")
assert_block_contains "gh pr create --body-file - from pr-writer blocks" "$out" "--body-file"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "cat $body_dir/ascii-1501.md | gh pr edit 1 -F -" "$session" "develop:pr-writer")
assert_block_contains "gh pr edit -F - from pr-writer blocks" "$out" "--body-file"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr create --title x --body-file $body_dir/ascii-1500.md && echo \"don't" "$session" "develop:pr-writer")
assert_block_contains "unclosed quote in gh pr create blocks" "$out" "--body-file"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook 'gh pr edit 1 --title "x' "$session" "develop:pr-writer")
assert_pass "gh pr edit with only --title passes even if it cannot be parsed" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook 'gh pr edit 1 --add-label bug' "$session" "develop:pr-writer")
assert_pass "gh pr edit --add-label from pr-writer passes" "$out"
rm -f "$(marker_file_for "$session")"

session=$(new_ready_session)
out=$(run_hook "gh pr create --title x --body-file $body_dir/ascii-1501.md" "$session")
assert_block_contains "the pr-writer check still comes before the length check" "$out" "develop:pr-writer"
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
