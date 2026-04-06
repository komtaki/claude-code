---
name: commit-push
description: Git CommitしてPushする手順。「コミットしてプッシュ」「commit push」「commit-push」と言われた時に使用する。
---

# Git Commit & Push 手順

commitスキルの手順でコミットした後、リモートにpushする。

## 手順

### 1. Commit

`/git:commit` スキルの手順に従ってコミットを作成する。

### 2. Push

コミットが成功したら、現在のブランチにpushする。

```bash
git push origin <現在のブランチ名>
```

リモートブランチが存在しない場合は `-u` フラグを付ける。

```bash
git push -u origin <現在のブランチ名>
```

### 3. 結果報告

push完了後、以下を報告する:

- コミットハッシュ（短縮形）
- コミットメッセージ
- pushしたブランチ名

## 注意事項

- pushに失敗した場合は原因を調査し、ユーザーに報告する
- force pushは行わない。必要な場合はユーザーに確認する
