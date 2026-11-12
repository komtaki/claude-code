#!/usr/bin/env bash
# usage: classify-diff.sh <repo-dir> [base-branch] [session_id]
# stdout: code | docs | shared
set -euo pipefail

repo_dir=${1:?repo-dir is required}
base=${2:-}
session=${3:-}

toplevel=$(git -C "$repo_dir" rev-parse --show-toplevel)
physical=$(cd "$toplevel" && pwd -P)
if [ -z "$base" ]; then
  base=$(git -C "$toplevel" symbolic-ref --short refs/remotes/origin/HEAD)
  base=${base#origin/}
fi

merge_base=$(git -C "$toplevel" merge-base "origin/$base" HEAD)
changed=$(git -C "$toplevel" -c core.quotepath=off diff --name-only "$merge_base" HEAD)

if [ -z "$changed" ]; then
  echo code
  exit 0
fi

if ! printf '%s\n' "$changed" | grep -qvE '\.md$|^docs/'; then
  echo docs
  exit 0
fi

tmp=${TMPDIR:-/tmp}
if [ -n "$session" ]; then
  records=("$tmp/claude-shared-impact-$session")
else
  # 記録の書き手はメインの session_id を使うが、サブエージェントはそれを知らないため、直近 24 時間の記録をすべて見る
  records=()
  while IFS= read -r f; do
    records+=("$f")
  done < <(find "$tmp" -maxdepth 1 -type f -name 'claude-shared-impact-*' -mmin -1440 2>/dev/null)
fi

belongs_to_repo() {
  local dir owner
  dir=$(dirname "$1")
  while [ ! -d "$dir" ]; do dir=$(dirname "$dir"); done
  owner=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ "$(cd "$owner" && pwd -P)" = "$physical" ]
}

for f in "${records[@]+"${records[@]}"}"; do
  [ -f "$f" ] || continue
  while IFS= read -r path; do
    if belongs_to_repo "$path"; then
      echo shared
      exit 0
    fi
  done < <(awk -v a="$toplevel/" -v b="$physical/" 'index($0, a) == 1 || index($0, b) == 1' "$f" | sort -u)
done

echo code
