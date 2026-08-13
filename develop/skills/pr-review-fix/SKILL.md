---
name: pr-review-fix
description: PRのレビューコメントを確認・対応する時に使用する。「レビュー確認」「レビューコメント見て」「review comments」「PRのコメント確認」などのキーワードでトリガーされる。
---

### レビューコメントの確認方法

1. **PR のレビューコメントを確認**

```sh
gh pr view [PR_NUMBER] --json comments --jq '.[] | {author: .user.login, body: .body, path: .path, line: .line, id: .id}'
```

2. **特定のディスカッション URL からコメントを確認**

```sh
gh api repos/[OWNER]/[REPO]/pulls/[PR_NUMBER]/comments --jq '.[] | select(.id == [COMMENT_ID])'
```

### コメントへの返信方針

コメント投稿者が **bot だと確定できる場合のみ**（`author.login` が `[bot]` サフィックス付き、または `user.type == "Bot"`）、1行で端的に返信する。

それ以外（人間のレビュアーかどうか確定できない場合を含む）は、返信を自動送信せず、返信案を提示してユーザーに判断を委ねる。
