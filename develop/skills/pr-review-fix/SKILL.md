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

インラインコメントは1件ずつ個別に返信する（まとめて1つの返信にしない）。

コメント投稿者が **bot だと確定できる場合のみ**（`author.login` が `[bot]` サフィックス付き、または `user.type == "Bot"`）、1行で端的に返信する。

それ以外（人間のレビュアーかどうか確定できない場合を含む）は、返信を自動送信せず、返信案を提示してユーザーに判断を委ねる。

**インラインコメントへの個別返信**

```sh
gh api repos/[OWNER]/[REPO]/pulls/[PR_NUMBER]/comments/[COMMENT_ID]/replies -f body="[REPLY_BODY]"
```

### コメントの resolve

返信後、対応済みのコメントは resolve する。REST API に resolve のエンドポイントはないため GraphQL を使う。

1. **コメント ID からスレッド ID を特定**

```sh
gh api graphql -f query='
{
  repository(owner: "[OWNER]", name: "[REPO]") {
    pullRequest(number: [PR_NUMBER]) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          comments(first: 1) {
            nodes { databaseId }
          }
        }
      }
    }
  }
}'
```

2. **スレッドを resolve**

```sh
gh api graphql -f query='
mutation {
  resolveReviewThread(input: {threadId: "[THREAD_ID]"}) {
    thread { isResolved }
  }
}'
```
