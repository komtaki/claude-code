---
name: ship
description: 依頼を実装してから PR を作り、レビュー対応を終えてマージ待ちにするまでに使用する。「PR にして」「実装して PR まで」「PR 出して」「ship」などのキーワードでトリガーされる。
---

# ship: 依頼から PR マージ待ちまで

「依頼から PR マージ待ちまで」の定義はここだけに置く。develop:pr-create（PR 作成の段）と develop:code-describe（lensdiff の資料）はここから呼ばれる。

## プロジェクト固有の追加

作業先の `AGENTS.md`・`CLAUDE.md` が、このスキルにゲートや手順を足すことがある（lensdiff レビューが要る PR の範囲、commit 前に読むページ、共有物の記録を書く hook など）。足された分はこのスキルの該当する段に差し込んで従う。両方が食い違うときは作業先の指示を優先する。

以下、`<skill-dir>` はこのスキルのベースディレクトリ（起動時に示される絶対パス）、`<repo-dir>` は対象リポジトリのディレクトリを指す。

## 0. 始める前に

- 使える skill があるか確認し、作業先の指示（上の節）を読む。
- PR の base を決める。既定は `origin/HEAD` のブランチ。Stack PR の上側では下側のブランチを base にし、以降の `<base>` はすべてそれを使う。

## 0.5 設計と計画（必要なとき）

依頼の解釈が 2 通り以上あり作るものが変わるとき、または実装が 3 タスク以上に分かれるときだけ行う。小さな修正では飛ばす。

- **設計書**: Claude Docs のアーティファクトに書く（`Artifact` の quickstart → Docs 型から作成）。リポジトリや `docs/` にファイルとして置かず、commit もしない。章は、意図と理由・目標/非目標/アンチゴール・決めたこと・実装者に任せること、の順にする。
- **実装者の目での確認**: 書き終えたら、会話を知らないサブエージェントに設計書だけを読ませ、「推測が要り、外すと作るものが変わる点」を挙げさせる。会話や既存コードで答えられるものは設計書に書き足し、実装者が決めてよいものは「設計者の判断」と明記する。残った点だけを 1 回でユーザーに聞く。
- **承認**: ユーザーが設計書を承認するまで実装に入らない。
- **計画**: タスクごとに、触るファイル・前のタスクから受け取る名前と形・テスト名と期待値を、scratchpad の計画ファイルに書く。計画も commit しない。

## 1. 差分の種類で段を決める

commit 後に次を実行する。`<repo-dir>` は cwd からの相対パスでも絶対パスでもよく、リポジトリ内のどのディレクトリでもよい。`<session_id>` は分かるときだけ渡す（省略すると直近 24 時間の記録を見る）。

```sh
bash <skill-dir>/classify-diff.sh <repo-dir> <base> [session_id]
```

exit code が 0 以外なら、`origin/<base>` がないか古いので、fetch するか base を直して実行し直す。出力は `code`・`docs`・`shared` の 1 語。

- `docs`: 変更がすべて `*.md` か `docs/` 配下
- `shared`: `${TMPDIR:-/tmp}/claude-shared-impact-<session_id>` に、同じリポジトリのファイルの記録があるとき。記録はプロジェクトの hook が共有物（共通関数・public API・module の変数の既定値など）の変更を検知して書く。記録を書く hook がないプロジェクトでは、共有物を変えると分かっていれば自分で `shared` とみなす
- `code`: それ以外

実装前で差分がないときは、依頼の内容から同じ基準で見込みを立て、commit 後に判定し直す。

| 段 | code | docs | shared |
| --- | --- | --- | --- |
| 実装 | サブエージェント | メイン可 | サブエージェント |
| simplify | 4 観点 | 4 観点 | 4 観点 |
| 資料（develop:code-describe） | 「lensdiff に渡す資料を作る」の条件に合えば | なし | 「対象外の参照元への影響」の節を必須 |
| lensdiff レビュー | 必須（人の承認） | 必須（人の承認） | 必須（人の承認） |
| AI レビュー | correctness ほか | 整合性だけ | 対象外の参照元の観点を必ず含める |
| PR・bot レビュー確認 | 必須 | 必須 | 必須 |

shared では、実装に入る前に参照元を grep で全数挙げ、依頼の対象と対象外に分ける。対象外の参照元の挙動は変えず、差分は呼び出し側が選ぶ opt-in にする。対象外の挙動が変わるなら、その一覧を示してユーザーの合意を取る。

作業先の指示が lensdiff レビューを省く PR では、3 の AI レビューの後に 5 へ進む。

## 2. 実装と simplify

1 の表の「実装」に従う。

サブエージェントに任せるときは、タスクごとに次を回す。0.5 の計画がなければ、依頼全体を 1 タスクとする。

1. **実装**: 実装担当に、そのタスクの要件だけ（計画の該当部分・前のタスクの名前と形・判断済みの事項）を渡す。テストを先に書いて失敗を確かめてから実装し、commit させる。実装担当にはさらにサブエージェントを起動させない。
2. **タスクレビュー**: 別のサブエージェントに、要件・実装担当の報告・差分を渡し、要件どおりか（過不足）と品質を判定させる。
3. **修正**: Critical・Important の指摘は実装担当に戻して直させ、修正分だけを再レビューする。3 回で収まらなければ、より能力の高いモデルの新しい実装担当に引き継ぐ。Minor は記録して最後の全体レビューに回す。
4. **全体レビュー**: 全タスクが終わったら、最も能力の高いモデルにブランチ全体をレビューさせ、指摘はまとめて 1 回で直す。

進み具合と判断は scratchpad の台帳ファイルに残し、文脈が要約されても台帳と `git log` から再開する。不具合を直すときは、原因を一次情報で突き止めてから直す。完了と報告する前に、テストやコマンドの出力を根拠として確かめる。

サブエージェントに任せた成果物は、メインエージェントが検品して責任を持つ。差分が従う規約（作業先の `AGENTS.md` など）を開いて差分の該当箇所と照らし、サブエージェントが回していない種類の検証を 1 つ以上自分で回す。

simplify は `simplify` スキルで、base との差分全体に 4 観点（再利用・簡素化・効率・抽象度）で行う。simplify と AI レビューの指摘は、意図した挙動を変えないものを採用し、不採用は理由を 6 の報告に残す（以下「指摘の採否の既定」）。

## 3. AI レビュー

レビュー観点ごとにサブエージェントを起動し、指摘を `kind: "finding"` の JSON 配列で scratchpad のファイルに書かせる。観点は 1 の表に従う。2 周目以降は、対象リポジトリで実行した `lensdiff decisions get` の結果を渡し、却下済みの指摘を出し直させない。却下の記録を消すときは `lensdiff decisions clear` を使う。

- severity が `error` の指摘（毎回失敗する、データを壊すなど）は、lensdiff を起動する前に直して commit する。
- `info` と `warn` は 4 で lensdiff に流す。
- lensdiff レビューを省く PR では、`info` と `warn` の採否を 2 の「指摘の採否の既定」で決め、採用分を commit する。

## 4. lensdiff レビュー

commit 済みのブランチを lensdiff で開いてユーザーのレビューを受ける。実装解説の承認もこのレビューで兼ねる。lensdiff は difit（yoshiko-pg/difit）の fork（`komtaki/lensdiff`）で、`difit` では代用しない。lensdiff の仕様（`--overview`、コメントの `kind` と JSON、終了時の出力）は `lensdiff` スキルの「Overview and Comment Kinds」「Output on Exit」に従う。

### 4.1 用意する

```sh
command -v lensdiff >/dev/null || npm install -g https://github.com/komtaki/lensdiff/releases/latest/download/lensdiff.tgz
[ -e ~/.claude/skills/lensdiff ] || npx skills add komtaki/lensdiff --skill lensdiff -g -a claude-code -y
```

- サンドボックスがあるなら外して実行する。最新にするときは、本体は `command -v` なしで実行し、スキルは `npx skills update lensdiff -g -y` を使う。
- 起動や `comment add` が 413 / `PayloadTooLargeError` で失敗したら、本体を最新にして起動し直す。
- `@parcel/watcher` の install script を飛ばす警告は無視する。

### 4.2 材料を作る

1 の表で資料が要るときは、`develop:code-describe` の「lensdiff に渡す資料を作る」に従い、`overview.md` と `explanations.json` を scratchpad に作る。shared では `overview.md` に「対象外の参照元への影響」の節を置き、参照元の数と、挙動が変わらない根拠（または合意済みの変化）を書く。修正を commit して起動し直すときは、`explanations.json` の行番号を HEAD のファイルで取り直す。

### 4.3 起動する

```sh
cd <repo-dir> && lensdiff --merge-base HEAD origin/<base> \
  --overview <scratchpad>/overview.md \
  --comment "$(cat <scratchpad>/explanations.json)"
```

バックグラウンドで、サンドボックスを外して実行する（Claude Code の Bash tool では `run_in_background: true` と `dangerouslyDisableSandbox: true`）。出力の `lensdiff server started on http://localhost:<port>` の port を、以降の `--port` に使う。lensdiff はユーザーがタブを閉じるかリロードすると終了する。

- `--merge-base` は値を取らないフラグ。`--merge-base origin/<base> HEAD` と書くと、差分なしでブラウザが開かないまま待機する。
- `--pr` は使わない。対応済みの GitHub スレッドを毎回取り込み、宣言ジャンプも動かないため。
- `--background` は付けない。コメントが返らなくなる。
- 宣言ジャンプは PATH の `ruby-lsp`・`typescript-language-server`・`pyright-langserver` を使う。見つからない言語は `unavailable` と表示されるだけ。

起動したら、3 の `info`・`warn` を 1 回の Bash 呼び出しで観点ごとに流す。

```sh
for r in correctness <ほかの観点>; do
  lensdiff reviewer start --port <port> "$r" &&
    lensdiff comment add --port <port> "$(cat <scratchpad>/findings-$r.json)"
  lensdiff reviewer done --port <port> "$r"
done
```

`comment add` が `Cannot connect to lensdiff server` で失敗したら、ユーザーはレビューを終えている。失敗として扱わず、その指摘は次の周に回す。

### 4.4 結果を受け取る

完了通知が届いたら出力ファイルを読む。exit code 0 以外は起動失敗なので、原因を直して再実行する。

- 最終行が `✅ Approved`、または `📝 Comments from review session:` のヘッダなしで終了したら承認（終了までの時間は問わない）。指摘付きの承認なら、指摘を直して commit する。
- `✅ Approved` なしで指摘が返ったら、修正して commit し、3〜4 をやり直す。
- 承認後は simplify と lensdiff を繰り返さない。承認後に AI レビューの指摘が出ても、lensdiff は起動し直さず、commit して PR を作る。
- 長時間終了しない場合は、タブが開かれていない可能性があるのでユーザーに確認する。

承認したら、PR を作る HEAD で承認 marker を書く。`<repo-dir>` はリポジトリの最上位ディレクトリにする。最上位でなければ何も書かずに失敗する。

```sh
bash <skill-dir>/approve.sh <repo-dir> <base>
```

marker は `${TMPDIR:-/tmp}/claude-lensdiff-approved/<リポジトリの物理パスの sha1 の先頭 12 桁>` に `<HEAD の sha> <base>` の 1 行を追記する。`gh pr create` を止める門番 hook をプロジェクトが持つときは、hook はこの marker を見る。

## 5. PR を作る

`develop:pr-create` を push の手順から呼ぶ（4.4 の「承認後は繰り返さない」に従う）。`gh pr create` には `--base <base>` を渡す。PR は pr-create の手順どおりドラフトで作る。依存先が未マージなら、依存を本文にも書く。

## 6. PR 作成後

### bot レビュー確認

Greptile などの bot は指摘を残したまま check を pass にする。`gh pr checks` だけで完了と判断せず、未 resolve スレッドを取得する。

```sh
gh api graphql -f query='
{
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: NUMBER) {
      reviewThreads(first: 20) {
        nodes { id isResolved isOutdated comments(first: 5) { nodes { author { login } path line body } } }
      }
    }
  }
}'
```

- bot のコメントは push から数分遅れるので、空なら間を置いて再取得する。
- bot の `isResolved: false` は `develop:pr-review-fix` で対応してから `resolveReviewThread` で resolve する。
- bot の指摘・CI の修正・base の merge は push だけで進める（4.4）。人に再レビューを頼むときは、資料の行番号を取り直す。

### 報告

聞かずに既定で決めたことを、最終報告と、PR 本文の既存の補足の節に「既定で決めたこと」として列挙する。テンプレートに節は足さない。

## 確認の基準

4 の lensdiff の承認、1 の shared での合意と、次の表の場面だけ止めてユーザーに聞く。それ以外は聞かずに既定で進め、上の「報告」に残す。

| 止めて聞く | 理由 |
| --- | --- |
| 本番リソースの削除など、取り消せない操作 | 取り消せない |
| 依頼の解釈が 2 通り以上あり、作るものが変わる | 作り直しになる |
| 人間のレビュアーのスレッドへの返信 | 自動で返さず、返信案を見せてユーザーが返す |
| commit の署名の失敗 | 署名は外さず、署名鍵の解除をユーザーに頼む |

| 聞かずに既定で進める（例） | 既定 |
| --- | --- |
| 依存先の PR が未マージ | pr-create の手順どおりドラフトで作り、依存を PR 本文にも書く |
| 役割・置き場所の分け方 | 既存の分担に合わせ、PR 本文に理由を書く |
| 子セッションからの判断依頼 | 親がこの 2 つの表で判断し、表にないものだけユーザーに上げる |
