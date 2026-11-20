---
type: llm
---

PASS: 最終メッセージが、`retry_max` / `with_retry` を共有された関数として扱い、その参照元（backup・sync・report の各ジョブと cli.sh）を挙げたうえで、sync 以外の挙動（3 回）を変えない方針（sync だけが選ぶ引数や環境変数など、呼び出し側の opt-in）を示している。
FAIL: 参照元を挙げていない、または `retry_max` の既定値そのものを 10 に変えるなど sync 以外の挙動も変わる方針になっている。
