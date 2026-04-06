---
name: rebase-push
description: PRをmainにrebaseしてforce-pushする時に使用する。「rebase」「rebase push」「PRをrebase」「リベース」などのキーワードでトリガーされる。
---

# PR Rebase & Push 手順

指定されたPRのブランチを最新のmain(またはデフォルトブランチ)にrebaseし、force-pushする。

## 手順

### 1. PR情報の取得

PR番号またはURLが指定された場合、ghコマンドでPR情報を取得する。

```bash
gh pr view <PR番号> --json headRefName,baseRefName,number,title
```

### 2. 現在の状態を確認

```bash
git status
git branch --show-current
```

未コミットの変更がある場合はユーザーに確認を取る。

### 3. デフォルトブランチを最新にする

```bash
git fetch origin main
```

※ デフォルトブランチが main 以外の場合は `baseRefName` を使用する。

### 4. PRブランチに切り替え

```bash
git checkout <headRefName>
git pull origin <headRefName>
```

### 5. Rebase実行

```bash
git rebase origin/main
```

コンフリクトが発生した場合:
- コンフリクトの内容をユーザーに報告する
- 解決方針についてユーザーの判断を仰ぐ
- 自動解決は行わない

### 6. Force Push

rebaseが成功したら force-with-lease で push する。

```bash
git push --force-with-lease origin <headRefName>
```

### 7. 元のブランチに戻る

作業前にいたブランチに戻る。

```bash
git checkout <元のブランチ>
```

## 注意事項

- `--force` ではなく `--force-with-lease` を使用する（他者の変更を上書きしない安全策）
- コンフリクト発生時は自動解決せず、必ずユーザーに確認する
- 作業前のブランチに必ず戻る
