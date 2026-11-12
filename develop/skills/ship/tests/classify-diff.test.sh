#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
classify="$script_dir/../classify-diff.sh"

root=$(mktemp -d "${TMPDIR:-/tmp}/classify-diff-test.XXXXXX")
trap 'rm -rf "$root"' EXIT
root=$(cd "$root" && pwd -P)
export TMPDIR="$root/tmp"
repo="$root/work/foo"
other="$root/work/bar"
session=test-session

failures=0

git_in() { git -C "$repo" "$@"; }

setup_repo() {
  rm -rf "$root/work" "$TMPDIR"
  mkdir -p "$repo" "$other" "$TMPDIR"
  git init -q "$repo"
  git_in config user.email test@example.com
  git_in config user.name test
  git_in config commit.gpgsign false
  git_in commit -q --allow-empty -m base
  git_in update-ref refs/remotes/origin/main HEAD
  git_in symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}

commit_files() {
  local f
  for f in "$@"; do
    mkdir -p "$repo/$(dirname "$f")"
    echo x >"$repo/$f"
  done
  git_in add -A
  git_in commit -q -m change
}

record() {
  printf '%s\n' "$2" >>"$TMPDIR/claude-shared-impact-$1"
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

setup_repo
commit_files README.md docs/guide.txt docs/nested/page.yml
assert_eq "docs_only" docs "$(bash "$classify" "$repo" main "$session")"

setup_repo
commit_files README.md llm-wiki/page.yml
assert_eq "non_docs_directory_is_code" code "$(bash "$classify" "$repo" main "$session")"

setup_repo
commit_files README.md src/app.ts
assert_eq "code" code "$(bash "$classify" "$repo" main "$session")"

setup_repo
commit_files README.md src/app.ts
record "$session" "$repo/src/app.ts"
assert_eq "shared_wins" shared "$(bash "$classify" "$repo" main "$session")"

setup_repo
commit_files src/app.ts
record "$session" "$other/src/app.ts"
assert_eq "shared_requires_same_repo" code "$(bash "$classify" "$repo" main "$session")"

setup_repo
commit_files src/app.ts
record other-session "$repo/src/app.ts"
assert_eq "shared_requires_same_session" code "$(bash "$classify" "$repo" main "$session")"

setup_repo
commit_files README.md
record "$session" "$repo/src/app.ts"
assert_eq "docs_only_ignores_shared_record" docs "$(bash "$classify" "$repo" main "$session")"

setup_repo
assert_eq "no_changes_is_code" code "$(bash "$classify" "$repo" main "$session")"

setup_repo
commit_files docs/a.md
assert_eq "base_defaults_to_origin_head" docs "$(bash "$classify" "$repo")"

setup_repo
commit_files src/app.ts
git_in update-ref refs/remotes/origin/feature HEAD
commit_files docs/a.md
assert_eq "stacked_base_compares_against_base_branch" docs "$(bash "$classify" "$repo" feature "$session")"
assert_eq "stacked_without_base_sees_lower_code" code "$(bash "$classify" "$repo" "" "$session")"

setup_repo
commit_files src/app.ts
record some-session-id "$repo/src/app.ts"
assert_eq "omitted_session_uses_recent_records" shared "$(bash "$classify" "$repo" main)"

setup_repo
commit_files src/app.ts
record some-session-id "$repo/src/app.ts"
touch -t 200001010000 "$TMPDIR/claude-shared-impact-some-session-id"
assert_eq "omitted_session_ignores_old_records" code "$(bash "$classify" "$repo" main)"

setup_repo
commit_files src/app.ts
: >"$TMPDIR/claude-shared-impact-some-session-main-0123456789ab"
assert_eq "omitted_session_ignores_empty_markers" code "$(bash "$classify" "$repo" main)"

setup_repo
nested="$repo/vendor/inner"
mkdir -p "$nested/src"
git init -q "$nested"
echo x >"$nested/src/app.ts"
echo 'vendor/' >"$repo/.gitignore"
commit_files tool.sh
record "$session" "$nested/src/app.ts"
assert_eq "nested_repo_record_is_not_shared" code "$(bash "$classify" "$repo" main "$session")"

setup_repo
commit_files docs/a.md
assert_eq "relative_repo_dir_from_parent" docs "$(cd "$root/work" && bash "$classify" foo main "$session")"
assert_eq "dot_from_inside_repo" docs "$(cd "$repo" && bash "$classify" . main "$session")"
assert_eq "subdirectory_resolves_to_repo" docs "$(cd "$repo/docs" && bash "$classify" . main "$session")"

setup_repo
commit_files src/app.ts
check_missing_base() { ! bash "$classify" "$repo" missing "$session" >/dev/null 2>&1; }
if check_missing_base; then
  echo "PASS: missing_base_exits_non_zero"
else
  echo "FAIL: missing_base_exits_non_zero"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
