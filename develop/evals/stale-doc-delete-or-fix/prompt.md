---
description: (b) 古い記述を見つけたら、書き換える前に規約上書いてよい種類かを照らし、消すか直すかを決める
runs: 1
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent, TodoWrite, Bash, Write, Edit]
---

このブランチの直前の commit で、リトライ回数を 3 回から 5 回に変えました。develop:ship で、この変更によって古くなった記述を直してください。

直した内容の commit までで止めてください。レビュー・simplify・lensdiff・push・PR には進まないでください。最後に、何をどう直したかと、その理由を報告してください。
