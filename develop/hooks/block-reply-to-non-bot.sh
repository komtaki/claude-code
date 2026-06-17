#!/usr/bin/env bash
# PreToolUse hook: PR / issue コメントへの返信時、返信先の投稿者が
# bot / app 以外（＝人間）の場合に block する。
#
# 対象ツール（GitHub MCP）:
#   - mcp__github__add_reply_to_pull_request_comment … PR レビューコメントへの返信
#   - mcp__github__add_issue_comment                  … issue / PR へのコメント
#   - mcp__github__add_comment_to_pending_review      … PR レビュー投稿（pending）
#   - mcp__github__pull_request_review_write          … PR レビュー投稿
#
# 判定方針:
#   返信先の投稿者を GitHub API で取得し、user.type == "Bot" もしくは
#   login が "[bot]" で終わる場合のみ許可する。
#   投稿者を特定できない場合（owner/repo/番号が無い・トークン無し・API 失敗）は
#   安全側に倒して block する（fail-closed）。
#
# stdout JSON で decision:block → ブロック理由を Claude に提示
# exit 0 かつ出力なし          → 通過

set -euo pipefail

INPUT=$(cat)

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
OWNER=$(printf '%s' "$INPUT" | jq -r '.tool_input.owner // ""')
REPO=$(printf '%s' "$INPUT" | jq -r '.tool_input.repo // ""')

# GitHub API を叩く。gh CLI を優先し、無ければ curl + トークンにフォールバック。
# 成功時は JSON を stdout に返す。失敗時は非ゼロ終了。
gh_api() {
  local path="$1"
  if command -v gh >/dev/null 2>&1; then
    gh api "$path" 2>/dev/null && return 0
  fi
  local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  if [ -n "$token" ] && command -v curl >/dev/null 2>&1; then
    curl -fsSL \
      -H "Authorization: Bearer ${token}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/${path}" 2>/dev/null && return 0
  fi
  return 1
}

# 指定 JSON 文字列から投稿者種別を判定し、"bot" / "human" / "" を返す。
classify_author() {
  printf '%s' "$1" | jq -r '
    (.user.type // "") as $t
    | (.user.login // "") as $l
    | if ($t | ascii_downcase) == "bot" then "bot"
      elif ($l | test("\\[bot\\]$"; "i")) then "bot"
      else "human" end
  ' 2>/dev/null || true
}

block() {
  printf '%s' "$1" | jq -Rs '{decision: "block", reason: .}'
  exit 0
}

# owner/repo が無い対象ツール以外はそのまま通過させる
case "$TOOL" in
  mcp__github__add_reply_to_pull_request_comment|\
  mcp__github__add_issue_comment|\
  mcp__github__add_comment_to_pending_review|\
  mcp__github__pull_request_review_write)
    ;;
  *)
    exit 0
    ;;
esac

if [ -z "$OWNER" ] || [ -z "$REPO" ]; then
  block "返信先の owner / repo を特定できなかったため、安全側でブロックしました。
返信は投稿者が bot / app のコメントに対してのみ許可されています。"
fi

API_PATH=""
TARGET_DESC=""

case "$TOOL" in
  mcp__github__add_reply_to_pull_request_comment)
    # 返信先はレビューコメントの投稿者
    CID=$(printf '%s' "$INPUT" | jq -r '.tool_input.commentId // .tool_input.comment_id // ""')
    if [ -z "$CID" ] || [ "$CID" = "null" ]; then
      block "返信先のレビューコメント ID を特定できなかったため、安全側でブロックしました。"
    fi
    API_PATH="repos/${OWNER}/${REPO}/pulls/comments/${CID}"
    TARGET_DESC="レビューコメント(ID: ${CID})の投稿者"
    ;;
  mcp__github__add_issue_comment)
    # 返信先は issue / PR の作成者
    NUM=$(printf '%s' "$INPUT" | jq -r '.tool_input.issue_number // .tool_input.issueNumber // ""')
    if [ -z "$NUM" ] || [ "$NUM" = "null" ]; then
      block "コメント対象の issue / PR 番号を特定できなかったため、安全側でブロックしました。"
    fi
    API_PATH="repos/${OWNER}/${REPO}/issues/${NUM}"
    TARGET_DESC="issue/PR #${NUM} の作成者"
    ;;
  mcp__github__add_comment_to_pending_review|\
  mcp__github__pull_request_review_write)
    # 返信先は PR の作成者
    NUM=$(printf '%s' "$INPUT" | jq -r '.tool_input.pullNumber // .tool_input.pull_number // ""')
    if [ -z "$NUM" ] || [ "$NUM" = "null" ]; then
      block "対象の PR 番号を特定できなかったため、安全側でブロックしました。"
    fi
    API_PATH="repos/${OWNER}/${REPO}/pulls/${NUM}"
    TARGET_DESC="PR #${NUM} の作成者"
    ;;
esac

RESP=$(gh_api "$API_PATH" || true)
if [ -z "$RESP" ]; then
  block "GitHub API から ${TARGET_DESC} を取得できなかったため、安全側でブロックしました。
（gh CLI が未認証、または GITHUB_TOKEN / GH_TOKEN が未設定の可能性があります）
返信は投稿者が bot / app のコメントに対してのみ許可されています。"
fi

KIND=$(classify_author "$RESP")
LOGIN=$(printf '%s' "$RESP" | jq -r '.user.login // "unknown"' 2>/dev/null || echo "unknown")

if [ "$KIND" = "bot" ]; then
  # bot / app への返信は許可
  exit 0
fi

if [ "$KIND" = "human" ]; then
  block "${TARGET_DESC} (@${LOGIN}) は bot / app ではありません。
人間ユーザーへの自動返信はブロックされています。返信は bot / app のコメントに対してのみ許可されています。"
fi

# 判定不能（パース失敗など）も安全側で block
block "${TARGET_DESC} の種別を判定できなかったため、安全側でブロックしました。
返信は投稿者が bot / app のコメントに対してのみ許可されています。"
