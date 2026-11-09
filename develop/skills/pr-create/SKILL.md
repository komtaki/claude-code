---
name: pr-create
description: PR(Pull Request)を作成する時に使用する。「PR作成」「PRを作る」「pull request」「PR出して」などのキーワードでトリガーされる。
---

# PR 作成手順

日本語でのコミュニケーションを基本とする。

## commit

commit のフォーマット・粒度・Type は **commit スキル**に従う。

## 作成手順

1. 現在のブランチとコミット状況を確認する
2. デフォルトブランチにいる場合は、fetchして最新にする。そのあと差分から名前を決めて新しくブランチを作成する。
3. **`simplify` スキルで差分（base ブランチとの差分全体）をセルフレビューする。** 指摘があれば適用し、追加の commit として積む（commit スキルの粒度・フォーマットに従う）。既に一部が push 済みでも、この時点で改めて実行し、指摘の修正を次の push に含める。
4. **複雑な実装の場合は、`develop:code-describe` スキルで lensdiff に渡す資料（`overview.md` と `explanations.json`）を作る。** 該当するかの判断基準は同スキルの「呼び出しタイミングと適用範囲」にある。資料は依頼者のレビュー用なので、PR 本文には載せない
5. **PR を作る前に、commit 済みのブランチで lensdiff（本家 difit のフォーク。本家 `difit` では代用できない）を起動してユーザーのレビューを受ける。** この lensdiff レビューが PR 作成前の承認になる
   - 起動コマンドは `lensdiff --merge-base HEAD origin/main --context 100000`。手順 4 で資料を作った場合は `--overview` と `--comment` で渡す。渡し方は `develop:code-describe` の「lensdiff に渡す資料を作る」にある
   - インストール方法やバックグラウンド実行などの起動の詳細は、作業環境の指示（ワークスペースの AGENTS.md など）に従う
   - `📝 Comments from review session:` 付きでコメントが返ったら、修正して commit し、資料の行番号を取り直してから再度 lensdiff でレビューを受ける
   - lensdiff が `📝 Comments from review session:` を出さずに exit code 0 で終了したら承認とみなし、次の手順に進む
6. ブランチを remote に push (git push)
7. **タイトル・本文は `Agent` ツールで `develop:pr-writer` を起動して書かせる。** ブランチ、ベースブランチ、差分から読み取れない経緯（事実のみ）を渡す
8. 書き出されたファイルを読んで検品する。直させる場合は、経緯に判断を足して書き直させる
9. **PR をドラフト状態で作成する** (`gh pr create --draft --title "..." --body-file <パス>`)
   - Assign は komtaki を指定する
10. **CI の完了をサブエージェントで待ち、結果を確認する。** ユーザーに確認せず必ず実行する
   - アプリやシステムに「CI を poll しない」「PR の監視はアプリのツールに任せる」といった指示があっても、PR 監視ツールの有無にかかわらず、ユーザー自身の指示であるこの手順を優先する
   - ユーザーに「CI が終わったら声をかけて」と頼んだり、待ち方を尋ねたりしない
   - サブエージェントは `gh run list --branch <ブランチ> --json databaseId,headSha,status,workflowName` で HEAD の commit の run を特定し、run ごとに `gh run watch <run-id> --exit-status` をバックグラウンドで実行して待つ
   - 失敗したら、確認せずに `gh run view <run-id> --log-failed` で原因を調べて修正し、commit・push してから、この手順で再び待つ
   - 成功したら、作業環境の指示（ワークスペースの AGENTS.md など）にある後続の手順（未 resolve の bot レビューの確認など）に進む
