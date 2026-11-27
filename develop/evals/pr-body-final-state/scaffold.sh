#!/usr/bin/env bash
set -euo pipefail
git init -q -b main .
git config user.name eval
git config user.email eval@example.invalid
git config commit.gpgsign false
mkdir -p src
cat > src/retry.sh <<'SH'
retry_max() {
  echo 3
}

with_retry() {
  local n=0 max
  max=$(retry_max)
  until "$@"; do
    n=$((n + 1))
    [ "$n" -ge "$max" ] && return 1
  done
}
SH
cat > README.md <<'MD'
# tinyretry

失敗したコマンドを再実行する小さなライブラリ。

リトライの設定は [src/retry.sh](src/retry.sh)。
MD
git add -A
git commit -qm init
git update-ref refs/remotes/origin/main HEAD
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

git switch -q -c feature/retry-env
cat > retry.conf <<'CONF'
max=3
CONF
cat > src/retry.sh <<'SH'
retry_max() {
  local conf=${TINYRETRY_CONF:-retry.conf}
  if [ -f "$conf" ]; then
    sed -n 's/^max=//p' "$conf"
  else
    echo 3
  fi
}

with_retry() {
  local n=0 max
  max=$(retry_max)
  until "$@"; do
    n=$((n + 1))
    [ "$n" -ge "$max" ] && return 1
  done
}
SH
git add -A
git commit -qm 'feat: リトライ回数を設定ファイル retry.conf で上書きできるようにする'

git rm -q retry.conf
cat > src/retry.sh <<'SH'
retry_max() {
  echo "${TINYRETRY_MAX:-3}"
}

with_retry() {
  local n=0 max
  max=$(retry_max)
  until "$@"; do
    n=$((n + 1))
    [ "$n" -ge "$max" ] && return 1
  done
}
SH
git add -A
git commit -qm 'refactor: 設定ファイルをやめ、環境変数 TINYRETRY_MAX で上書きする'
