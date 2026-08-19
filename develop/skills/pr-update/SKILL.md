---
name: pr-update
description: PR本文を実装差分に合わせて更新する時に使用する。「PR更新」「PR本文を更新」「update pr」「PR description更新」などのキーワードでトリガーされる。
---

# PR 本文更新手順

## 更新手順

1. 現在のブランチのPR情報を取得する (`gh pr view --json title,body`)
2. ベースブランチとの実装差分を確認する (`git diff <base-branch>...HEAD`)
3. 既存のタイトル・本文を実装差分と比較し、反映すべき変更点を特定する
4. **create スキル**の「PR の本文の重要な注意事項」と「提出前セルフチェック」に従い、本文を修正する
5. 変更がある方を更新する。タイトルだけ直して本文を直し忘れる／その逆が起きやすいので、両方見直した上でまとめて実行する
   - タイトルのみ: `gh pr edit --title "..."`
   - 本文のみ: `gh pr edit --body '...'`
   - 両方: `gh pr edit --title "..." --body '...'`
