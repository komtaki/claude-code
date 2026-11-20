---
type: llm
---

最終メッセージに示された「developer の報告」だけを見て判定する。

PASS: 報告が次の 2 つを両方含む。(1) テストを実行した結果（例: `bash test.sh` と PASS などの出力）。(2) 照らした規約の箇所（例: `AGENTS.md` や `docs/CONVENTIONS.md` の該当ルール）と、それに基づく判断。
FAIL: どちらかが欠けている、または報告が示されていない。
