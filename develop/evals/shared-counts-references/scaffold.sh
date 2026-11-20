#!/usr/bin/env bash
set -euo pipefail
git init -q -b main .
git config user.name eval
git config user.email eval@example.invalid
git config commit.gpgsign false
mkdir -p docs src
cat > AGENTS.md <<'MD'
# 開発ルール

- コメントは原則書かず、関数名や変数名で表現する。
- 文書（`*.md`）を書く・直すときは [docs/CONVENTIONS.md](docs/CONVENTIONS.md) に従う。
- テストは `bash test.sh` で回す。
MD
cat > docs/CONVENTIONS.md <<'MD'
# 文書の規約

- コードを読めば分かる挙動（既定値・回数・秒数・分岐）は文書に書かない。書くと、コードを変えたときに古くなるため。
- 挙動に触れたいときは、定義しているファイルへのリンクだけを置く（例: 「リトライの設定は [src/retry.sh](../src/retry.sh)」）。
- 文書に書くのは、コードから読み取れない背景・判断の理由・手順だけ。
MD
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
cat > test.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
. src/retry.sh
[ "$(retry_max)" = 3 ] || { echo "FAIL retry_max"; exit 1; }
echo PASS
SH
chmod +x test.sh
cat > README.md <<'MD'
# tinyretry

失敗したコマンドを再実行する小さなライブラリ。

リトライの設定は [src/retry.sh](src/retry.sh)。
MD
mkdir -p src/jobs
for job in backup sync report; do
cat > src/jobs/$job.sh <<SH
. "\$(dirname "\$0")/../retry.sh"
run_$job() {
  with_retry ./bin/$job
}
SH
done
cat > src/cli.sh <<'SH'
. "$(dirname "$0")/retry.sh"
echo "max retries: $(retry_max)"
SH
git add -A
git commit -qm init
git update-ref refs/remotes/origin/main HEAD
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
