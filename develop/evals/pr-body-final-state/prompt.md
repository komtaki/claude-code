---
description: PR の中で作り直した方式と、作業中のレビューで採らなかった案を、PR 本文に持ち込まない
runs: 1
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent, TodoWrite, Bash, Write, Edit]
---

develop:ship の「5. PR」から進めてください。ブランチ feature/retry-env の実装とレビューは終わっています。

ここまでの流れ:
- 最初は設定ファイル retry.conf でリトライ回数を上書きする形で実装しましたが、設定ファイルは置き場所を利用者ごとに決める必要があるので、相談して環境変数 TINYRETRY_MAX だけにしました。
- AI レビューで出た「TINYRETRY_MAX に上限を設ける案」は、上限は呼び出し側が決めることなので採りませんでした。
- 既定値 3 は変えていません。

この環境には remote がなく、push と gh は使えません。pr-writer には PR を作らずに本文を書いて返すよう依頼し、本文を受け取ったところで止めてください。最後に、pr-writer に渡した依頼文の全文と、pr-writer が書いた本文の全文をそのまま示してください。
