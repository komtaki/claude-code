---
name: cleanup
description: 削除済みブランチとworktreeをクリーンアップする時に使用する。「cleanup」「クリーンアップ」「ブランチ整理」「不要なブランチを削除」などのキーワードでトリガーされる。
---

# Git Cleanup: 削除済みブランチとWorktreeの削除

リモートで削除済みのブランチと、不要なworktreeをクリーンアップする手順。

**確認なしで即座に実行すること。** 途中でユーザーに確認を求めない。
ただし未コミットの変更があるworktreeはスキップし、最後のサマリーで報告する。

## 手順

### 1. リモート追跡情報を更新

```bash
git fetch --prune
```

### 2. mainブランチにきりかえ

```bash
git switch main
```

### 3. 不要なworktreeを削除

worktreeが参照しているブランチは削除できないため、ブランチ削除より先に実行する。

```bash
# 現在のworktree一覧を表示
git worktree list
```

各worktreeについて:
1. `git -C <worktree_path> status --short` で未コミットの変更を確認
2. **変更なし** → `git worktree remove <path>` で削除
3. **変更あり** → スキップ（最後に報告）

```bash
# ディレクトリが存在しないworktreeを一括削除
git worktree prune
```

### 4. 不要なローカルブランチを削除

#### 4a. リモートが削除済み（gone）のブランチ

```bash
# 一括削除（確認不要）
git branch -vv | grep ': gone]' | awk '{print $1}' | xargs git branch -D
```

#### 4b. リモート未追跡のローカル専用ブランチ

`grep ': gone]'` はリモート追跡が設定されていたブランチのみ対象。
pushされていないローカル専用ブランチで、worktreeにも紐づいていないものも削除する。

```bash
# リモート追跡なし（[origin/...] が無い）かつ main/現在ブランチ以外、かつworktree未使用（+マーカーなし）
git branch -vv | grep -v '\[origin/' | grep -v '^\*' | grep -v '^+' | grep -v '^ *main ' | grep -v '^ *master '
```

該当ブランチがあれば `git branch -D` で一括削除する。

### 5. サマリーを出力

最後に以下をまとめて報告する:

- 削除したworktree
- 削除したブランチ
- スキップしたworktree（未コミット変更あり）とその変更ファイル一覧
- 残存しているブランチ一覧 (`git branch -vv`)
- 残存しているworktree一覧 (`git worktree list`)