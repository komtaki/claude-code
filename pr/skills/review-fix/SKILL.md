---
description: レビューコメントの確認方法
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
