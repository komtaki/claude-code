#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hook="$script_dir/../check-comment-body.sh"

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

assert_pass "gh pr comment ending with (Claude)" \
  'gh pr comment 14 --body "対応しました (Claude)"'

assert_block "gh pr comment missing (Claude) suffix" \
  'gh pr comment 14 --body "対応しました"'

assert_pass "gh pr review ending with (Claude)" \
  'gh pr review 14 --comment --body "LGTM (Claude)"'

assert_block "gh pr review missing (Claude) suffix" \
  'gh pr review 14 --comment --body "LGTM"'

assert_pass "gh pr review without --body has nothing to validate" \
  'gh pr review 14 --approve'

assert_pass "gh api reply with -f body=\"...\" ending with (Claude)" \
  'gh api repos/o/r/pulls/1/comments/2/replies -f body="対応しました (Claude)"'

assert_block "gh api reply with -f body=\"...\" missing (Claude) suffix" \
  'gh api repos/o/r/pulls/1/comments/2/replies -f body="対応しました"'

assert_block "gh api PATCH with -f body='...' missing (Claude) suffix" \
  "gh api -X PATCH repos/o/r/pulls/comments/3 -f body='修正' "

assert_pass "gh api with -f body='...' ending with (Claude)" \
  "gh api -X PATCH repos/o/r/pulls/comments/3 -f body='修正 (Claude)'"

assert_pass "gh api with --raw-field 'body=...' ending with (Claude)" \
  "gh api repos/o/r/issues/1/comments --raw-field 'body=対応しました (Claude)'"

assert_block "gh api with --raw-field 'body=...' missing (Claude) suffix" \
  "gh api repos/o/r/issues/1/comments --raw-field 'body=対応しました'"

assert_pass "gh api with -F \"body=...\" ending with (Claude)" \
  'gh api repos/o/r/issues/1/comments -F "body=対応しました (Claude)"'

assert_block "gh api with -F \"body=...\" missing (Claude) suffix" \
  'gh api repos/o/r/issues/1/comments -F "body=対応しました"'

assert_block "gh api with --field body=unquoted missing (Claude) suffix" \
  'gh api repos/o/r/issues/1/comments --field body=done'

assert_block "gh api after && missing (Claude) suffix" \
  'cd repo && gh api repos/o/r/pulls/1/comments/2/replies -f body="対応しました"'

assert_pass "gh api graphql without body field is ignored" \
  "gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: \"x\"}) { thread { id } } }'"

assert_pass "gh api read without body field is ignored" \
  "gh api repos/o/r/pulls/1/comments --jq '.[].body'"

assert_pass "gh api -F body=@file cannot be validated statically" \
  'gh api repos/o/r/pulls/1/comments/2/replies -F body=@reply.md'

assert_pass "gh api unresolved command substitution cannot be validated statically" \
  'gh api repos/o/r/pulls/1/comments/2/replies -f body="$(build-comment)"'

assert_pass "gh api mentioned mid-string is not treated as the command" \
  'git commit -m "fix: gh api -f body=x の挙動を修正"'

if [ "$failures" -gt 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "All tests passed"
