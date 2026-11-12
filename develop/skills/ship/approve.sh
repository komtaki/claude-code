#!/usr/bin/env bash
# usage: approve.sh <repo-dir> <base>
set -euo pipefail

repo_dir=${1:?repo-dir is required}
base=${2:?base is required}

repo=$(cd "$repo_dir" && pwd -P)
toplevel=$(git -C "$repo" rev-parse --show-toplevel)
if [ "$(cd "$toplevel" && pwd -P)" != "$repo" ]; then
  echo "approve.sh: $repo_dir is not the top level of a git repository" >&2
  exit 1
fi
sha=$(git -C "$repo" rev-parse HEAD)
# 門番 hook が同じ式で marker を探すため、式を変えるときは hook 側も合わせる
marker="${TMPDIR:-/tmp}/claude-lensdiff-approved/$(printf '%s' "$repo" | shasum | cut -c1-12)"

mkdir -p "$(dirname "$marker")"
printf '%s %s\n' "$sha" "$base" >> "$marker"
