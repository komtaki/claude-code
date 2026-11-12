#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
approve="$script_dir/../approve.sh"

root=$(mktemp -d "${TMPDIR:-/tmp}/approve-test.XXXXXX")
trap 'rm -rf "$root"' EXIT
root=$(cd "$root" && pwd -P)
export TMPDIR="$root/tmp"
repo="$root/work/foo"
marker_dir="$TMPDIR/claude-lensdiff-approved"

failures=0

setup() {
  rm -rf "$root/work" "$TMPDIR"
  mkdir -p "$TMPDIR" "$repo/src"
  git init -q "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test
  git -C "$repo" config commit.gpgsign false
  git -C "$repo" commit -q --allow-empty -m base
}

check() {
  local desc="$1"
  shift
  if "$@"; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc"
    failures=$((failures + 1))
  fi
}

expected_marker() {
  printf '%s/%s' "$marker_dir" "$(printf '%s' "$repo" | shasum | cut -c1-12)"
}

marker_has_head() {
  grep -qx "$(git -C "$repo" rev-parse HEAD) main" "$(expected_marker)"
}

marker_is_only_file() {
  [ "$(ls -A "$marker_dir")" = "$(basename "$(expected_marker)")" ]
}

no_marker() {
  [ ! -e "$marker_dir" ] || [ -z "$(ls -A "$marker_dir")" ]
}

setup
bash "$approve" "$repo" main
check "absolute_repo_writes_head_and_base" marker_has_head
check "marker_name_is_sha1_prefix_of_physical_toplevel" marker_is_only_file

setup
(cd "$repo" && bash "$approve" . main)
check "dot_from_inside_repo" marker_has_head

setup
(cd "$root/work" && bash "$approve" foo main)
check "relative_from_parent" marker_has_head

setup
ln -s "$repo" "$root/work/link"
bash "$approve" "$root/work/link" main
check "symlink_resolves_to_physical_path" marker_has_head

setup
bash "$approve" "$repo" main
git -C "$repo" commit -q --allow-empty -m next
bash "$approve" "$repo" main
check "second_approval_keeps_previous_lines" bash -c "[ \"\$(wc -l <'$(expected_marker)' | tr -d ' ')\" = 2 ]"
check "second_approval_records_new_head" marker_has_head

setup
check "missing_repo_exits_non_zero" bash -c "! bash '$approve' '$root/work/missing' main 2>/dev/null"
check "missing_repo_writes_nothing" no_marker

setup
check "missing_base_exits_non_zero" bash -c "! bash '$approve' '$repo' 2>/dev/null"
check "missing_base_writes_nothing" no_marker

setup
check "non_git_dir_exits_non_zero" bash -c "! bash '$approve' '$root/work' main 2>/dev/null"
check "non_git_dir_writes_nothing" no_marker

setup
check "subdirectory_exits_non_zero" bash -c "! bash '$approve' '$repo/src' main 2>/dev/null"
check "subdirectory_writes_nothing" no_marker

if [ "$failures" -gt 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
