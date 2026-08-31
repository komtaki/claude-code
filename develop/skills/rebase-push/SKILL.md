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

コンフリクトが発生した場合、以下の基準で対応する。

自力解決してよいケース:
- ロックファイル(`package-lock.json` / `yarn.lock` / `pnpm-lock.yaml` / `Gemfile.lock` 等)→ 再生成コマンドを実行して解決する
- 空白・改行・フォーマットのみの差分
- 両側の変更が別々の箇所に対するもので、単純に両方を残せば意味が保たれる場合
- 一方の変更がもう一方と同一内容の場合

上記に該当し自力解決した場合:
- 解決内容を `git diff` で確認し、変更点をユーザーに報告する
- `git add <file>` してから `git rebase --continue` に進む
- 可能であればテスト/lintを実行し、解決が壊れていないことを確認する

自力解決しない(ユーザーに確認する)ケース:
- 同じ行・同じロジックに対して意味の異なる変更が競合している場合
- ビジネスロジックの矛盾が疑われる場合
- 解決方針に複数の妥当な選択肢があり、どちらを採用すべきか判断がつかない場合

この場合はコンフリクトの内容を報告し、ユーザーの判断を待ってから `git rebase --continue` する。

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
- コンフリクトは可能な場合は自力解決し、解決内容を必ずユーザーに報告する
- ロジックが競合する等、判断がつかないコンフリクトは自動解決せず必ずユーザーに確認する
- 作業前のブランチに必ず戻る
