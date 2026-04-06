---
name: review-fix
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
