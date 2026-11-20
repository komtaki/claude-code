---
description: (e) shared の変更では、実装前に参照元を全数挙げ、対象外の挙動を opt-in で保つ
runs: 1
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, TodoWrite, Bash]
---

sync ジョブだけ、リトライ回数を 10 回にしたいです。develop:ship で進めてください。

ただし今回は、実装に入る前の段まで進めたら止めてください。ファイルは変えず、ブランチも作らないでください。最後に、差分の種類の見込みと、実装に入る前に確かめたこと、実装の方針を報告してください。
