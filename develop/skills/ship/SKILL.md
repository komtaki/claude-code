---
name: ship
description: 依頼を実装してから PR を作り、レビュー対応を終えてマージ待ちにするまでに使用する。「PR作成」「PRを作る」「pull request」「PR出して」「PR にして」「実装して PR まで」「ship」「PR更新」「PR本文を更新」「update pr」「PR description更新」などのキーワードでトリガーされる。
---

# ship: 依頼から PR マージ待ちまで

作業先の `AGENTS.md`・`CLAUDE.md` が足すゲートや手順は該当する段に差し込み、食い違えば作業先を優先する。

## 0. 始める前に

使える skill と作業先の指示を確認する。デフォルトブランチにいたら fetch し、依頼から名前を決めてブランチを作る。base は `origin/HEAD` のブランチ（Stack PR の上側では下側のブランチ）とし、以降の `<base>` はこれを指す。

## 0.5 設計と計画（解釈が 2 通り以上で作るものが変わるとき、または 3 タスク以上のとき）

- **設計書**: Claude Docs のアーティファクト（`Artifact` の quickstart → Docs 型）に、意図と理由・目標/非目標/アンチゴール・決めたこと・実装者に任せること、の章で書く。
- **実装者の目での確認**: 会話を知らないサブエージェントに設計書だけを読ませ、「推測が要り、外すと作るものが変わる点」を挙げさせる。会話や既存コードで答えられるものは書き足し、実装者が決めてよいものは「設計者の判断」と明記し、残りを 1 回でユーザーに聞く。ユーザーの承認を得てから実装に入る。
- **計画**: タスクごとに、触るファイル・前のタスクから受け取る名前と形・テスト名と期待値を scratchpad の計画ファイルに書く。

## 1. 差分の種類で段を決める

commit 後に実行する。`<skill-dir>` はこのスキルのベースディレクトリ、`<repo-dir>` は対象リポジトリ内の任意のディレクトリ、`<session_id>` は分かるときだけ渡す（省略時は直近 24 時間の記録を見る）。

```sh
bash <skill-dir>/classify-diff.sh <repo-dir> <base> [session_id]
```

exit code が 0 以外なら fetch するか base を直して再実行する。出力は、変更がすべて `*.md` か `docs/` 配下なら `docs`、プロジェクトの hook が `${TMPDIR:-/tmp}/claude-shared-impact-<session_id>` に同じリポジトリの共有物（共通関数・public API・module の変数の既定値など）の変更を記録していれば `shared`、それ以外は `code`。共有物を変えると分かっていれば記録がなくても `shared` とする。差分がまだなければ依頼から見込み、commit 後に判定し直す。

| 段 | code | docs | shared |
| --- | --- | --- | --- |
| 実装 | サブエージェント | メイン可 | サブエージェント |
| 資料（develop:code-describe） | 「自分の実装を説明する」の複雑な実装に当たれば | なし | 「対象外の参照元への影響」の節（複雑な実装でなくても作る） |
| AI レビュー | correctness ほか | 整合性 | 対象外の参照元の観点を含める |

shared では、実装前に参照元を grep で全数挙げて依頼の対象と対象外に分け、差分は呼び出し側が選ぶ opt-in にする。対象外の挙動が変わるなら、その一覧を示してユーザーの合意を取る。

## 2. 実装と simplify

サブエージェントに任せるときは、タスクごとに次を回す（計画がなければ依頼全体を 1 タスクとする）。

1. **実装**: 実装担当にそのタスクの要件（計画の該当部分・前のタスクの名前と形・判断済みの事項）を渡し、テストを先に書いて失敗を確かめてから実装し commit させる。
2. **タスクレビュー**: 別のサブエージェントに要件・報告・差分を渡し、過不足と品質を判定させる。
3. **修正**: Critical・Important は実装担当に直させて修正分を再レビューし、3 回で収まらなければ能力の高いモデルの新しい実装担当に引き継ぐ。Minor は全体レビューに回す。
4. **全体レビュー**: 最も能力の高いモデルにブランチ全体をレビューさせて指摘をまとめて直す。これを 3 の correctness 観点とする。

- 進み具合と判断は scratchpad の台帳に残し、台帳と `git log` から再開する。不具合は原因を一次情報で突き止めてから直し、完了はテストやコマンドの出力で確かめる。成果物はメインエージェントが検品する。差分が従う規約（作業先の `AGENTS.md` など）と差分を照らし、サブエージェントが回していない種類の検証を 1 つ以上回す。
- commit は `develop:commit` に従う。署名に失敗したら `git -c commit.gpgsign=false commit ...` で commit し、確認の基準の「既定で決めたこと」に残す。
- simplify は `simplify` スキルで、差分全体に 4 観点（再利用・簡素化・効率・抽象度）で行う。simplify と AI レビューの指摘は意図した挙動を保つものを採用し、不採用の理由を確認の基準の「既定で決めたこと」に残す（「指摘の採否の既定」）。

## 3. AI レビュー

観点ごとにサブエージェントを起動し、指摘を `kind: "finding"` の JSON 配列で scratchpad に書かせる。2 周目以降は `lensdiff decisions get` の結果を渡して却下済みを除かせる。`error`（毎回失敗する、データを壊すなど）は lensdiff の前に直して commit し、`info`・`warn` は 4 で lensdiff に流す。作業先が lensdiff レビューを省く PR では、`info`・`warn` を「指摘の採否の既定」で採否を決めて commit し、5 へ進む。

## 4. lensdiff レビュー

commit 済みのブランチを lensdiff（`komtaki/lensdiff`）で開き、ユーザーのレビュー（実装解説の承認を兼ねる）を受ける。オプション・JSON・終了時の出力は `lensdiff` スキルに従う。未導入ならサンドボックスを外して入れる。

```sh
command -v lensdiff >/dev/null || npm install -g https://github.com/komtaki/lensdiff/releases/latest/download/lensdiff.tgz
[ -e ~/.claude/skills/lensdiff ] || npx skills add komtaki/lensdiff --skill lensdiff -g -a claude-code -y
```

1. 資料が要るときは `develop:code-describe` の「lensdiff に渡す資料を作る」で `overview.md` と `explanations.json` を scratchpad に作る。
2. `<repo-dir>` で `lensdiff --merge-base HEAD origin/<base>` をサンドボックスを外してシェルのバックグラウンド実行で起動し、3 の `info`・`warn` を流す。`--merge-base` は値を取らないフラグで、引数は `HEAD origin/<base>` の順に置く。lensdiff は既定のフォアグラウンドモードで動かす（`--background` を付けるとコメントが返らない）。
3. 終了後に出力を読む。最終行が `✅ Approved`、または `📝 Comments from review session:` のヘッダなしの終了なら承認で、指摘付きなら直して commit する。
4. それ以外で指摘が返ったら、直して commit し、資料の行番号を HEAD で取り直して手順 2〜4 をやり直す。
5. 承認したら、PR を作る HEAD で `bash <skill-dir>/approve.sh <repo-dir> <base>`（`<repo-dir>` はリポジトリの最上位）を実行して marker を書く（プロジェクトの門番 hook が読む）。以降の修正は commit して 5 へ進む。

## 5. PR を作る

1. ブランチを push する。
2. `Agent` ツールで `develop:pr-writer` を起動し、ブランチ・base・差分から読み取れない経緯（事実のみ）を渡してタイトルと本文を書かせる。
3. 書き出されたファイルを検品し、直させるときは経緯に判断を足す。依存先の PR が未マージなら依存を本文に書く。
4. `gh pr create --draft --base <base> --assignee komtaki --title "..." --body-file <パス>` で作る。
5. CI を監視する。PR 監視ツール（Claude Code desktop の `ccd_pr` など）があれば bind して auto-fix をオンにし、6 へ進む。なければサブエージェントに `gh pr checks <番号> --watch --fail-fast` をバックグラウンドで待たせ、失敗は `gh run view <run-id> --log-failed` で原因を調べて直し、push して待ち直す。

## 6. PR 作成後

bot（Greptile など）は指摘を残したまま check を pass にするため、`develop:pr-review-fix` の手順で未 resolve スレッドを取得し、対応して resolve する。push 直後に空なら約 5 分後に 1 回取り直す。修正は commit・push で進め、人に再レビューを頼むときは資料の行番号を取り直す。

1. 差分が変わったとき、または頼まれたときは PR 本文を更新する。`gh pr view <番号> --json body` から、差分から読み取れない事実（経緯、参照 URL、但し書き）を抜き出す。pr-writer は既存本文を読まないため、ここで拾う。
2. `develop:pr-writer` に PR 番号・base と 1 の事実を渡し、タイトルと本文を新規に書かせる。
3. 書き出されたファイルを検品し、`gh pr edit <番号> --title "..." --body-file <パス>` で反映する。

## 確認の基準

4 の lensdiff の承認、1 の shared での合意、次の表の場面でユーザーに聞く。それ以外は既定で進め、最終報告と PR 本文の既存の補足の節に「既定で決めたこと」として列挙する。

| 止めて聞く | 理由 |
| --- | --- |
| 本番リソースの削除など、取り消せない操作 | 取り消せない |
| 依頼の解釈が 2 通り以上あり、作るものが変わる | 作り直しになる |
| 人間のレビュアーのスレッドへの返信 | 返信案を見せ、ユーザーが返す |
