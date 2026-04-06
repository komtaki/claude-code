---
name: commit-push
description: Git CommitしてPushする時に使用する。「コミットしてプッシュ」「commit push」「commit-push」「コミットして push」などのキーワードでトリガーされる。
---

# Git Commit & Push 手順

commitスキルの手順でコミットした後、リモートにpushする。

## 手順

### 1. Commit

Skill toolで `/git:commit` を呼び出してコミットを作成する。

### 2. Push

コミットが成功したら、現在のブランチにpushする。

リモートブランチの存在を確認する。

```bash
git ls-remote --heads origin <現在のブランチ名>
```

出力がある場合（リモートブランチが存在する場合）:

```bash
git push origin <現在のブランチ名>
```

出力が空の場合（リモートブランチが存在しない場合）:

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
