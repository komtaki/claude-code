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
3. **simplify・lensdiff の資料・lensdiff レビューは `develop:ship` の 2〜4 で済ませておく。** このスキルは `develop:ship` の PR 作成の段（push 以降）にあたる。`develop:ship` を経ずに呼ばれたら、先に `develop:ship` を起動してその流れに乗る（lensdiff の承認を飛ばさないため）
4. ブランチを remote に push (git push)
5. **タイトル・本文は `Agent` ツールで `develop:pr-writer` を起動して書かせる。** ブランチ、ベースブランチ、差分から読み取れない経緯（事実のみ）を渡す
6. 書き出されたファイルを読んで検品する。直させる場合は、経緯に判断を足して書き直させる
7. **PR をドラフト状態で作成する** (`gh pr create --draft --title "..." --body-file <パス>`)
   - Assign は komtaki を指定する
8. **CI を監視し、結果に対応する。** ユーザーに確認せず必ず実行する
   - アプリに PR 監視ツール（Claude Code desktop の `ccd_pr` など）があれば、PR を bind して auto-fix をオンにし、CI 失敗・コンフリクト・レビューコメントの対応を任せる。auto-fix は成功を通知しないため、オンにしたら成功を待たずに後続の手順に進む
   - ツールを使えないときは、サブエージェントに待たせる。サブエージェントは `gh pr checks <PR 番号> --watch --fail-fast` をバックグラウンドで実行して待つ
   - 失敗したら、確認せずに、失敗した check のリンクから run を特定して `gh run view <run-id> --log-failed` で原因を調べて修正し、commit・push してから、この手順で再び待つ
   - 成功したら、`develop:ship` の「6. PR 作成後」（未 resolve の bot レビューの確認など）に進む
