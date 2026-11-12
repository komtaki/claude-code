---
name: ship
description: 依頼を実装して PR を作り、レビュー対応を終えてマージ待ちにするまでの流れ。実装から PR まで進める依頼、PR の作成、PR 本文の更新のときに使う。「PR作成」「PRを作る」「pull request」「PR出して」「PR にして」「実装して PR まで」「ship」「PR更新」「PR本文を更新」「update pr」「PR description更新」などでトリガーされる。
---

# ship: 依頼から PR マージ待ちまで

ユーザーに聞くのは末尾の「止めて聞く場面」だけにし、それ以外は既定で決めて進め、決めたことを最後に報告する。作業先の `AGENTS.md`・`CLAUDE.md` が足す手順は該当する段に入れ、食い違えば作業先に従う。4 の lensdiff レビューは、どの作業先でも行う。

## 1. 準備

- デフォルトブランチにいたら fetch してブランチを作る。base は `origin/HEAD` のブランチ（Stack PR の上側は下側のブランチ）。
- 依頼の解釈が割れるとき、または 3 タスク以上になるときは、先に設計する。設計書は Claude Docs のアーティファクト（`Artifact` の quickstart → Docs 型）に書き、会話を知らないサブエージェントに読ませて「推測が要り、外すと作るものが変わる点」を挙げさせる。答えられる点は書き足し、残りを 1 回で聞き、承認を得てから実装する。タスクごとの計画（触るファイル・受け渡す名前と形・テストと期待値）は scratchpad に置く。

## 2. 実装

差分の種類は `bash <skill-dir>/classify-diff.sh <repo-dir> <base> [session_id]` で判定する（`<skill-dir>` はこのスキルのベースディレクトリ）。実装前は依頼から見込む。

- `docs`（変更が `*.md` か `docs/` 配下だけ）: メインエージェントが編集する。
- `code`: サブエージェントに任せる。
- `shared`（共通関数・public API・既定値を変える）: サブエージェントに任せる。実装前に参照元を grep で全数挙げ、依頼の対象外の挙動は opt-in で保つ。対象外の挙動が変わるなら一覧を示して合意を取る。

サブエージェントにはタスクごとに、要件だけを渡して実装（テストを先に書く）→ 別のサブエージェントでレビュー → Critical・Important を修正、を回す。3 回で収まらなければ能力の高いモデルに引き継ぐ。最後に最も能力の高いモデルでブランチ全体をレビューし、まとめて直す。進み具合は scratchpad の台帳に残す。成果物は作業先の規約と照らし、サブエージェントが回していない検証を 1 つ以上自分で回してから受け取る。

commit は `develop:commit` に従う。署名に失敗したら `git -c commit.gpgsign=false commit` で commit する。

## 3. simplify と AI レビュー

`simplify` スキルで差分全体を 4 観点で見直し、意図した挙動を保つ指摘を採用する。続けて観点ごとにサブエージェントで AI レビューし、指摘を `kind: "finding"` の JSON で scratchpad に書かせる（`code` は correctness ほか、`docs` は整合性、`shared` は対象外の参照元を含める。2 の全体レビューを correctness とする）。`error` は直して commit し、`info`・`warn` は 4 で lensdiff に流す。

## 4. lensdiff レビュー

人の承認を得る段。ツールの使い方は `lensdiff` スキルに従う。未導入ならサンドボックスを外して入れる。

```sh
command -v lensdiff >/dev/null || npm install -g https://github.com/komtaki/lensdiff/releases/latest/download/lensdiff.tgz
[ -e ~/.claude/skills/lensdiff ] || npx skills add komtaki/lensdiff --skill lensdiff -g -a claude-code -y
```

1. 複雑な実装と `shared` では、`develop:code-describe` で `overview.md` と `explanations.json` を作る。`shared` の `overview.md` には「対象外の参照元への影響」の節（参照元の数と、挙動が変わらない根拠または合意済みの変化）を置く。
2. `<repo-dir>` で `lensdiff --merge-base HEAD origin/<base>` を、サンドボックスを外してバックグラウンドのシェルで起動し、`info`・`warn` を流す。
3. 最終行が `✅ Approved`、またはコメントなしで終わったら承認。指摘付きの承認なら直して commit する。承認なしの指摘は、直して commit し、資料の行番号を取り直して 2 からやり直す。
4. 承認したら `bash <skill-dir>/approve.sh <repo-top> <base>` で承認を記録する（プロジェクトの門番 hook が読む）。以降の修正は commit して 5 へ進む。

## 5. PR

1. push し、`develop:pr-writer` にブランチ・base・差分から読めない経緯を渡してタイトルと本文を書かせる。読んで検品し、未マージの依存があれば本文に書く。
2. `gh pr create --draft --base <base> --assignee komtaki --title "..." --body-file <パス>`。
3. CI は `ccd_pr` があれば bind して auto-fix に任せる。なければサブエージェントに `gh pr checks <番号> --watch --fail-fast` で待たせ、失敗は `gh run view <run-id> --log-failed` で原因を見て直す。
4. bot は指摘を残したまま check を通すので、`develop:pr-review-fix` で未 resolve スレッドに対応する（push 直後に空なら約 5 分後に 1 回取り直す）。
5. 差分が変わったら本文を更新する。`gh pr view --json body` から差分で読めない事実を拾い、pr-writer に書き直させて `gh pr edit` で反映する。
6. 既定で決めたことを、最終報告と PR 本文の補足に並べる。

## 止めて聞く場面

| 場面 | 理由 |
| --- | --- |
| 本番リソースの削除など、取り消せない操作 | 戻せない |
| 依頼の解釈が割れ、作るものが変わる | 作り直しになる |
| `shared` で対象外の挙動が変わる | 他の利用者に影響する |
| 人間のレビュアーへの返信 | 返信案を見せ、本人が返す |
| lensdiff の承認 | 人の判断そのもの |
