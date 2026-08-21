#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hook="$script_dir/../warn-added-comments.sh"

failures=0

run_hook() {
  printf '%s' "$1" | bash "$hook"
}

added_count() {
  local msg
  msg=$(run_hook "$1" | jq -r '.systemMessage // empty')
  printf '%s' "$msg" | grep -oE '[0-9]+' | head -1
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (expected [$expected], got [$actual])"
    failures=$((failures + 1))
  fi
}

write_payload() {
  jq -n --arg content "$1" --arg fp "$2" \
    '{tool_name:"Write", tool_input:{file_path:$fp, content:$content}}'
}

edit_payload() {
  jq -n --arg old "$1" --arg new "$2" --arg fp "$3" \
    '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:$old, new_string:$new}}'
}

docstring_only=$'def resolve_role_id(session):\n    """Resolve role_id -> organizations.id on the caller\'s own session.\n\n    Bypasses OrganizationService, which always opens its own session -- a\n    second connection/transaction alongside the one this script uses for\n    its UPDATEs.\n    """\n    return session.role_id\n'
assert_eq "Write: python docstring with no #-comments is detected" \
  "6" "$(added_count "$(write_payload "$docstring_only" "example.py")")"

old_no_comment=$'x = 1\n'
new_hash_comment=$'# added a comment\nx = 1\n'
assert_eq "Edit: existing # comment detection still works" \
  "1" "$(added_count "$(edit_payload "$old_no_comment" "$new_hash_comment" "example.py")")"

new_slash_comment=$'// added a comment\nvar x = 1;\n'
assert_eq "Edit: existing // comment detection still works" \
  "1" "$(added_count "$(edit_payload "$old_no_comment" "$new_slash_comment" "example.js")")"

old_no_docstring=$'def foo():\n    return 1\n'
new_multiline_docstring=$'def foo():\n    """\n    Rationale for this workaround.\n    """\n    return 1\n'
assert_eq "Edit: multi-line docstring counts each line once (no double count)" \
  "3" "$(added_count "$(edit_payload "$old_no_docstring" "$new_multiline_docstring" "example.py")")"

new_oneliner_docstring=$'def foo():\n    """Just a short summary."""\n    return 1\n'
assert_eq "Edit: single-line docstring counts as exactly one line" \
  "1" "$(added_count "$(edit_payload "$old_no_docstring" "$new_oneliner_docstring" "example.py")")"

two_docstrings=$'def foo():\n    """First summary."""\n    return 1\n\n\ndef bar():\n    """Second summary."""\n    return 2\n'
assert_eq "Write: multiple separate docstrings in one blob are all detected" \
  "2" "$(added_count "$(write_payload "$two_docstrings" "example.py")")"

md_content=$'"""not a docstring in markdown"""\n'
md_out=$(run_hook "$(write_payload "$md_content" "example.md")")
assert_eq "Write: .md files are skipped regardless of content" "" "$md_out"

if [ "$failures" -gt 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "All tests passed"
