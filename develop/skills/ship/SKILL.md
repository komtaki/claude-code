---
name: ship
description: 依頼を実装して PR を作り、レビュー対応を終えてマージ待ちにするまでの流れ。実装から PR まで進める依頼、PR の作成、PR 本文の更新のときに使う。「PR作成」「PRを作る」「pull request」「PR出して」「PR にして」「実装して PR まで」「ship」「PR更新」「PR本文を更新」「update pr」「PR description更新」などでトリガーされる。
---

# ship: 依頼から PR マージ待ちまで

作り手に依頼するときと成果物を受け取るときは、[inspection.md](inspection.md) に従う。ユーザーに聞くのは末尾の「止めて聞く場面」だけにし、それ以外は既定で決めて進め、決めたことを最後に報告する。ただし「1. 準備」で `設計: 要` とした依頼は、判断を委ねられた点も既定で決めず、設計書の承認を得る。作業先の `AGENTS.md`・`CLAUDE.md` が足す手順は該当する段に入れ、食い違えば作業先に従う。手順は差分の規模で省かない。省いてよいのは作業先が定めるときだけ。門番 hook に手順の抜けで止められたら、止められた段の手順を頭から回す（hook を通すことを目的にしない）。

## 1. 準備

- デフォルトブランチにいたら fetch してブランチを作る。base は `origin/HEAD` のブランチ（Stack PR の上側は下側のブランチ）。
- 依頼の解釈が割れるとき、または 3 タスク以上になるときは、先に設計する。タスクは、触るファイル（とそのテスト）ごとに 1 件と数える。解釈が割れる点は、外すと作るものが変わる点。依頼文に手順が書いてあっても、判断を委ねられた点（「必要なら」「判断してよい」など）が 1 つでもあれば、既定で決めずに `設計: 要` にする。実装に入る前に、判定を scratchpad の台帳の先頭に `設計: 要｜不要（タスク N 件: …。解釈が割れる点: …）` と書く。作るものが広がったら（文面の修正のはずがスクリプトを作る、など）、その場で判定し直し、`要` になったら実装を止めて設計に戻る。設計書は Claude Docs のアーティファクト（`Artifact` の quickstart → Docs 型）に書き、会話を知らないサブエージェントに読ませて「推測が要り、外すと作るものが変わる点」を挙げさせる。答えられる点は書き足し、残りを 1 回で聞き、承認を得てから実装する。タスクごとの計画（触るファイル・受け渡す名前と形・テストと期待値）は scratchpad に置く。

## 2. 実装

差分の種類は `bash <skill-dir>/classify-diff.sh <repo-dir> <base> [session_id]` で判定する（`<skill-dir>` はこのスキルのベースディレクトリ）。実装前は依頼から見込む。

- `docs`（変更が `*.md` か `docs/` 配下だけ）: メインエージェントが編集する。
- `code`: サブエージェントに任せる。
- `shared`（共通関数・public API・既定値を変える）: サブエージェントに任せる。実装前に参照元を grep で全数挙げ、依頼の対象外の挙動は opt-in で保つ。対象外の挙動が変わるなら一覧を示して合意を取る。

サブエージェントにはタスクごとに、要件だけを渡して実装（テストを先に書く）→ 別のサブエージェントでレビュー → Critical・Important を修正、を回す。3 回で収まらなければ能力の高いモデルに引き継ぐ。最後に最も能力の高いモデルでブランチ全体をレビューし、まとめて直す。進み具合は scratchpad の台帳に残す。

テストは、差分で変わった利用者から見える挙動を確かめる。消したもの・存在しないものが出ないことを確かめるテストは書かず、消したものを参照していた既存テストを直す。

不具合を直すときは、まず再現させ、原因をログ・コード・データなどの一次情報で突き止めてから直す。完了と報告する前にテストやコマンドを実行し、その出力を根拠として示す。

commit は `develop:commit` に従う。署名に失敗したら `git -c commit.gpgsign=false commit` で commit する。

## 3. simplify と AI レビュー

`simplify` スキルで差分全体を 4 観点で見直し、意図した挙動を保つ指摘を採用する。続けて観点ごとにサブエージェントで AI レビューし、指摘を `kind: "finding"` の JSON で scratchpad に書かせる（`code` は correctness ほか、`docs` は整合性、`shared` は対象外の参照元を含める。2 の全体レビューを correctness とする）。`error` は直して commit し、`info`・`warn` は 4 で lensdiff に流す。simplify で採用しなかった指摘も、メインエージェントが `warn` の finding として findings JSON に書き起こし、4 で lensdiff に流して人が決める。

## 4. lensdiff レビュー

人の承認を得る段。ツールの使い方は `lensdiff` スキルに従う。未導入ならサンドボックスを外して入れる。

```sh
command -v lensdiff >/dev/null || npm install -g https://github.com/komtaki/lensdiff/releases/latest/download/lensdiff.tgz
[ -e ~/.claude/skills/lensdiff ] || npx skills add komtaki/lensdiff --skill lensdiff -g -a claude-code -y
```

1. `develop:code-describe` で `overview.md` と `explanations.json` を作る。`shared` の `overview.md` には「対象外の参照元への影響」の節（参照元の数と、挙動が変わらない根拠または合意済みの変化）を置く。
2. `<repo-dir>` で `lensdiff --merge-base HEAD origin/<base> --overview <overview.md> --comment "$(cat <explanations.json>)" --comment "$(cat <findings.json>)"` を、サンドボックスを外してバックグラウンドのシェルで起動する。`<findings.json>` は「3. simplify と AI レビュー」の `info`・`warn` の指摘。
3. 最終行が `✅ Approved`、またはタブを閉じてコメントが出なかったときは承認（閉じることが承認の意思表示なので聞き直さない）。指摘付きの承認なら直して commit する。承認なしの指摘は、直して commit し、解説と指摘の行番号を取り直し、修正で増えた hunk の解説を足して 2 からやり直す。
4. 承認したら `bash <skill-dir>/approve.sh <repo-top> <base>` で承認を記録する（プロジェクトの門番 hook が読む）。以降の修正は commit して 5 へ進む。

## 5. PR

1. push し、`develop:pr-writer` にブランチ・base・差分から読めない経緯（未マージの依存、既定で決めたこと）を渡して、draft PR を作らせる。
2. `gh pr view` で本文を検品し、直す点は同じ pr-writer に `SendMessage` で伝える。少量でも自分では直さない。書き手と検品者が分かれないと検品にならないため（`check-pr-command.sh` が止める）。
3. CI は `ccd_pr` があれば bind して auto-fix に任せる。なければサブエージェントに `gh pr checks <番号> --watch --fail-fast` で待たせ、失敗は `gh run view <run-id> --log-failed` で原因を見て直す。
4. bot は指摘を残したまま check を通すので、`develop:pr-review-fix` で未 resolve スレッドに対応する（push 直後に空なら約 5 分後に 1 回取り直す）。
5. 差分が変わったら、`gh pr view --json body` から差分で読めない事実を拾い、PR 番号と一緒に pr-writer に渡して書き直させる。
6. 既定で決めたことを、最終報告に並べる。

## 止めて聞く場面

| 場面 | 理由 |
| --- | --- |
| 本番リソースの削除など、取り消せない操作 | 戻せない |
| 台帳が `設計: 要` のときの設計書の承認（依頼の解釈が割れ、作るものが変わる） | 作り直しになり、作るものが広がり続ける |
| `shared` で対象外の挙動が変わる | 他の利用者に影響する |
| 人間のレビュアーへの返信 | 返信案を見せ、本人が返す |
| lensdiff の承認 | 人の判断そのもの |
