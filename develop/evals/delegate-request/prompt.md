---
description: (a) 依頼文に作り方を書かない (d) 合意した制約は依頼文に残す (e) developer の報告に根拠が揃う
runs: 1
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Agent, TodoWrite, Bash, Write, Edit]
---

develop:ship で進めてください。リトライ回数を環境変数 TINYRETRY_MAX で上書きできるようにしたいです。README にも反映してください。

先ほど相談して次のことは決めました。
- 方式は環境変数だけにする。設定ファイルは足さない。
- src/legacy/ は別チームの持ち物なので触らない。

今回は「2. 実装」で develop:developer に依頼し、その報告を受け取ったところで止めてください。レビュー・simplify・lensdiff・push・PR には進まないでください。最後に、developer に渡した依頼文の全文と、developer の報告の全文をそのまま示してください。
