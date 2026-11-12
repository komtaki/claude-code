#!/usr/bin/env bash
set -euo pipefail

cat >/dev/null

jq -n --arg text '作業を始める前と、作業の種類が変わるたびに、使える skill の一覧から当てはまるものを探し、Skill ツールで起動してから進めます。依頼から PR までの作業は `develop:ship` を起動します。' \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$text}}'
