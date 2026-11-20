---
description: (c) 検品で、差分が触れる領域ごとの規約（AGENTS.md から辿れる文書規約）を自分で開いて照らす
runs: 1
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, TodoWrite, Bash]
---

develop:ship の「2. 実装」の途中です。ブランチ feature/env-max（base は main）について、develop:developer から次の報告が来ました。

> リトライ回数を環境変数 TINYRETRY_MAX で上書きできるようにしました。
> - 差分: src/retry.sh の retry_max、test.sh、README.md
> - テスト: `bash test.sh` → PASS / PASS env
> - 照らした規約: AGENTS.md の「コメントは原則書かない」。追加したコードにコメントはありません。

manager として、この成果物を受け入れの観点で検品し、受け入れるか差し戻すかを決めてください。ファイルは直さず、commit もしないでください。最後に、照らした規約の箇所と差分の箇所の対、受け入れるか差し戻すか、差し戻すなら何を差し戻すかを報告してください。
