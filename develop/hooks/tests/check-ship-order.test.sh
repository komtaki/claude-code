#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check="$script_dir/../check-ship-order.sh"

failures=0
test_counter=0

export TMPDIR="${TMPDIR:-/tmp}"
work_dir=$(cd "$(mktemp -d "$TMPDIR/check-ship-order-test.XXXXXX")" && pwd -P)
trap 'rm -rf "$work_dir"' EXIT

agents_repo="$work_dir/agents"
claude_repo="$work_dir/claude"
bare_repo="$work_dir/bare"
space_repo="$work_dir/sp ace"
linked_repo="$work_dir/linked"
plain_dir="$work_dir/plain"
for repo in "$agents_repo" "$claude_repo" "$bare_repo" "$space_repo" "$linked_repo"; do
  mkdir -p "$repo"
  git -C "$repo" init -q
done
mkdir -p "$plain_dir"
touch "$agents_repo/AGENTS.md" "$agents_repo/CLAUDE.md" "$claude_repo/CLAUDE.md" "$space_repo/AGENTS.md" "$linked_repo/CLAUDE.md" "$plain_dir/AGENTS.md"
ln -s CLAUDE.md "$linked_repo/AGENTS.md"
mkdir -p "$agents_repo/sub"
ln -s "$agents_repo" "$work_dir/agents-link"
inspection="$work_dir/plugin/skills/ship/inspection.md"
other_inspection="$work_dir/cache/develop/9.9.9/skills/ship/inspection.md"

new_transcript() {
  test_counter=$((test_counter + 1))
  local path="$work_dir/transcript-$test_counter.jsonl"
  : > "$path"
  printf '%s' "$path"
}

add_tool_use() {
  local transcript="$1" name="$2" input="$3" cwd="${4-$work_dir}" sidechain="${5:-false}"
  jq -cn --arg name "$name" --argjson input "$input" --arg cwd "$cwd" --argjson side "$sidechain" \
    '{type:"assistant", isSidechain:$side} + (if $cwd == "" then {} else {cwd:$cwd} end) + {message:{role:"assistant", content:[{type:"tool_use", id:"toolu_x", name:$name, input:$input}]}}' >> "$transcript"
}

add_skill() {
  local transcript="$1" skill
  shift
  for skill in "$@"; do
    add_tool_use "$transcript" Skill "$(jq -cn --arg s "$skill" '{skill:$s}')"
  done
}

add_command() {
  jq -cn --arg c "$2" \
    '{type:"user", isSidechain:false, message:{role:"user", content:("<command-message>x</command-message>\n<command-name>" + $c + "</command-name>\n<command-args></command-args>")}}' >> "$1"
}

add_command_array() {
  jq -cn --arg c "$2" \
    '{type:"user", isSidechain:false, message:{role:"user", content:[{type:"text", text:("<command-name>" + $c + "</command-name>")}]}}' >> "$1"
}

add_read() {
  add_tool_use "$1" Read "$(jq -cn --arg p "$2" '{file_path:$p}')" "$work_dir" "${3:-false}"
}

add_bash_read() {
  add_tool_use "$1" Bash "$(jq -cn --arg c "$2" '{command:$c}')" "${3:-}"
}

add_compact() {
  printf '%s\n' '{"type":"system","subtype":"compact_boundary","isSidechain":false,"content":"Conversation compacted"}' >> "$1"
}

caller_fields() {
  case "$1" in
    subagent) printf '%s' '{"agent_id":"a1","agent_type":"general-purpose"}' ;;
    agent-main) printf '%s' '{"agent_type":"reviewer"}' ;;
    *) printf '%s' '{}' ;;
  esac
}

run_agent() {
  local tool="$1" transcript="$2" caller="${3:-}"
  jq -n --arg tool "$tool" --arg t "$transcript" --argjson extra "$(caller_fields "$caller")" \
    '{tool_name:$tool, tool_input:{prompt:"x"}, session_id:"s", transcript_path:$t} + $extra' | bash "$check"
}

run_bash() {
  local cmd="$1" transcript="$2" cwd="$3" caller="${4:-}"
  jq -n --arg cmd "$cmd" --arg t "$transcript" --arg cwd "$cwd" --argjson extra "$(caller_fields "$caller")" \
    '{tool_name:"Bash", tool_input:{command:$cmd}, session_id:"s", cwd:$cwd, transcript_path:$t} + $extra' | bash "$check"
}

now() {
  python3 -c 'import time; print(time.time())'
}

assert_pass() {
  local desc="$1" out="$2"
  if [ -z "$out" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (expected no block, got [$out])"
    failures=$((failures + 1))
  fi
}

assert_block_contains() {
  local desc="$1" out="$2" needle="$3" decision reason
  decision=$(printf '%s' "$out" | jq -r '.decision // empty' 2>/dev/null || true)
  reason=$(printf '%s' "$out" | jq -r '.reason // empty' 2>/dev/null || true)
  if [ "$decision" = "block" ] && printf '%s' "$reason" | grep -qF -- "$needle"; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (decision=[$decision] reason=[$reason])"
    failures=$((failures + 1))
  fi
}

assert_reason_lacks() {
  local desc="$1" out="$2" needle="$3" reason
  reason=$(printf '%s' "$out" | jq -r '.reason // empty' 2>/dev/null || true)
  if printf '%s' "$reason" | grep -qF -- "$needle"; then
    echo "FAIL: $desc (reason=[$reason])"
    failures=$((failures + 1))
  else
    echo "PASS: $desc"
  fi
}

for command in "/develop:ship" "/ship"; do
  t=$(new_transcript)
  add_command "$t" "$command"
  out=$(run_agent "Agent" "$t")
  assert_block_contains "command [$command] starts the ship gates" "$out" "inspection.md"
done

t=$(new_transcript)
add_command_array "$t" "/develop:ship"
out=$(run_agent "Agent" "$t")
assert_block_contains "command in a text element array starts the ship gates" "$out" "inspection.md"

for command in "/shipit" "/develop:shipping" "/simplify"; do
  t=$(new_transcript)
  add_command "$t" "$command"
  out=$(run_agent "Agent" "$t")
  assert_pass "command [$command] does not start the ship gates" "$out"
done

t=$(new_transcript)
jq -cn '{type:"user", isSidechain:false, message:{role:"user", content:"これを /ship して。develop:ship の inspection.md を読む"}}' >> "$t"
add_skill "$t" "develop:commit"
out=$(run_agent "Agent" "$t")
assert_pass "mentioning ship in a prompt does not start the ship gates" "$out"

t=$(new_transcript)
add_skill "$t" "develop:commit"
out=$(run_agent "Agent" "$t")
assert_pass "Agent without ship passes" "$out"
out=$(run_bash "lensdiff --merge-base HEAD origin/main" "$t" "$agents_repo")
assert_pass "lensdiff without ship passes" "$out"

out=$(run_agent "Agent" "$work_dir/missing.jsonl")
assert_pass "Agent with a missing transcript passes" "$out"
out=$(jq -n '{tool_name:"Agent", tool_input:{prompt:"x"}, session_id:"s"}' | bash "$check")
assert_pass "Agent without transcript_path passes" "$out"
out=$(run_bash "lensdiff ." "$work_dir/missing.jsonl" "$agents_repo")
assert_pass "lensdiff with a missing transcript passes" "$out"

t=$(new_transcript)
printf '%s\n' '{"kind":"turn","role":"assistant","calls":[{"tool":"Skill","args":{"skill":"develop:ship"}}]}' >> "$t"
out=$(run_agent "Agent" "$t")
assert_block_contains "unreadable transcript with a ship invocation blocks Agent" "$out" "transcript の形式が読めない"
out=$(run_bash "lensdiff ." "$t" "$bare_repo")
assert_block_contains "unreadable transcript with a ship invocation blocks lensdiff" "$out" "transcript の形式が読めない"
out=$(run_bash "git status" "$t" "$bare_repo")
assert_pass "unreadable transcript does not block other Bash commands" "$out"

t=$(new_transcript)
printf '%s\n' '{"type":"user","payload":"<command-name>/develop:ship</command-name>"}' >> "$t"
out=$(run_agent "Agent" "$t")
assert_block_contains "unreadable user line with a ship command blocks Agent" "$out" "transcript の形式が読めない"

t=$(new_transcript)
jq -cn '{type:"user", isSidechain:false, message:{role:"user", content:[{type:"tool_result", tool_use_id:"toolu_x", content:"<command-name>/develop:ship</command-name>"}]}}' >> "$t"
jq -cn '{type:"assistant", isSidechain:false, message:{role:"assistant", content:[{type:"text", text:"<command-name>/develop:ship</command-name>"}]}}' >> "$t"
out=$(run_agent "Agent" "$t")
assert_pass "ship command text in a tool_result or assistant text does not block Agent" "$out"
out=$(run_bash "lensdiff ." "$t" "$agents_repo")
assert_pass "ship command text in a tool_result or assistant text does not block lensdiff" "$out"

t=$(new_transcript)
add_skill "$t" "develop:ship"
chmod 000 "$t"
out=$(run_agent "Agent" "$t")
assert_block_contains "transcript that cannot be opened blocks Agent" "$out" "transcript を開けない"
out=$(run_bash "lensdiff ." "$t" "$bare_repo")
assert_block_contains "transcript that cannot be opened blocks lensdiff" "$out" "transcript を開けない"
out=$(run_bash "git status" "$t" "$bare_repo")
assert_pass "transcript that cannot be opened does not block other Bash commands" "$out"
chmod 600 "$t"

t=$(new_transcript)
add_skill "$t" "develop:ship"
out=$(run_agent "Agent" "$t")
assert_block_contains "Agent before reading inspection.md blocks" "$out" "inspection.md"
assert_block_contains "Agent block asks to put the evidence into the request" "$out" "作り手が返す根拠"
assert_block_contains "Agent block asks to copy the viewpoints into the task list" "$out" "メインエージェントが見る観点"
assert_block_contains "Agent block applies the evidence only to the matching section" "$out" "A〜D"
assert_block_contains "Agent block asks to read it again after compact" "$out" "/compact"
assert_block_contains "Agent block accepts Bash reads" "$out" "Bash"
out=$(run_agent "Task" "$t")
assert_block_contains "Task before reading inspection.md blocks" "$out" "inspection.md"
out=$(run_agent "Agent" "$t" "subagent")
assert_pass "Agent from a subagent passes" "$out"
out=$(run_agent "Agent" "$t" "agent-main")
assert_block_contains "Agent from a main thread with agent_type blocks" "$out" "inspection.md"
add_read "$t" "$inspection" true
out=$(run_agent "Agent" "$t")
assert_block_contains "inspection.md read on a sidechain does not count" "$out" "inspection.md"
add_read "$t" "$inspection"
out=$(run_agent "Agent" "$t")
assert_pass "Agent after the main agent reads inspection.md passes" "$out"

t=$(new_transcript)
add_skill "$t" "develop:ship"
add_read "$t" "$other_inspection"
out=$(run_agent "Agent" "$t")
assert_pass "inspection.md of another plugin cache version counts" "$out"

t=$(new_transcript)
add_skill "$t" "develop:ship"
add_read "$t" "$work_dir/plugin/skills/shipping/inspection.md"
out=$(run_agent "Agent" "$t")
assert_block_contains "inspection.md of another skill does not count" "$out" "inspection.md"

t=$(new_transcript)
add_command "$t" "/develop:ship"
add_bash_read "$t" "cat $inspection" "$work_dir"
out=$(run_agent "Agent" "$t")
assert_pass "inspection.md read with Bash cat passes" "$out"

t=$(new_transcript)
add_skill "$t" "develop:ship"
add_bash_read "$t" "cd $work_dir/plugin/skills && sed -n 1,80p ship/inspection.md" "$bare_repo"
out=$(run_agent "Agent" "$t")
assert_pass "inspection.md read with Bash after cd passes" "$out"

t=$(new_transcript)
add_skill "$t" "develop:ship"
add_bash_read "$t" "cd $work_dir/plugin/skills/ship; cat inspection.md"
out=$(run_agent "Agent" "$t")
assert_pass "Bash read without cwd is resolved from the leading cd" "$out"

t=$(new_transcript)
add_skill "$t" "develop:ship"
add_bash_read "$t" "cat \$SK/inspection.md" "$work_dir"
out=$(run_agent "Agent" "$t")
assert_block_contains "Bash read through an unresolved variable does not count" "$out" "inspection.md"
add_bash_read "$t" "ls $inspection" "$work_dir"
out=$(run_agent "Agent" "$t")
assert_block_contains "Bash ls of inspection.md does not count" "$out" "inspection.md"
add_bash_read "$t" "cd \$HOME_UNKNOWN; cat skills/ship/inspection.md" "$work_dir/plugin"
out=$(run_agent "Agent" "$t")
assert_block_contains "Bash read after an unresolved cd does not count" "$out" "inspection.md"
add_bash_read "$t" "ls; SK=$work_dir/plugin/skills/ship; ls \$SK; cat \"\${SK}/inspection.md\"" "$work_dir"
out=$(run_agent "Agent" "$t")
assert_pass "Bash read through a variable assigned in the same command counts" "$out"

t=$(new_transcript)
add_skill "$t" "develop:ship"
add_bash_read "$t" "cat $inspection" "$work_dir"
add_compact "$t"
out=$(run_agent "Agent" "$t")
assert_block_contains "inspection.md read only before compact blocks" "$out" "inspection.md"
add_read "$t" "$inspection"
out=$(run_agent "Agent" "$t")
assert_pass "inspection.md read again after compact passes" "$out"

t=$(new_transcript)
add_skill "$t" "develop:ship" "develop:simplify"
add_read "$t" "$inspection"
add_read "$t" "$agents_repo/AGENTS.md"
add_compact "$t"
add_compact "$t"
out=$(run_agent "Agent" "$t")
assert_block_contains "after compact Agent blocks until inspection.md is read again" "$out" "inspection.md"
out=$(run_bash "lensdiff ." "$t" "$agents_repo")
assert_block_contains "after compact lensdiff blocks until AGENTS.md is read again" "$out" "AGENTS.md"
assert_reason_lacks "after compact simplify stays counted" "$out" "3. simplify と AI レビュー"
add_bash_read "$t" "cat AGENTS.md" "$agents_repo"
out=$(run_bash "lensdiff ." "$t" "$agents_repo")
assert_pass "lensdiff passes after AGENTS.md is read with Bash after compact" "$out"

t=$(new_transcript)
add_skill "$t" "develop:ship"
add_compact "$t"
out=$(run_agent "Agent" "$t")
assert_block_contains "ship invoked before compact still starts the ship gates" "$out" "inspection.md"

t=$(new_transcript)
add_skill "$t" "develop:ship"
add_read "$t" "$agents_repo/AGENTS.md"
out=$(run_bash "lensdiff --merge-base HEAD origin/main" "$t" "$agents_repo")
assert_block_contains "lensdiff without simplify blocks" "$out" "3. simplify と AI レビュー"
assert_block_contains "simplify block asks to stop and ask the user" "$out" "止めてユーザーに聞く"
assert_reason_lacks "simplify block does not allow the work target to skip" "$out" "作業先が定めるときだけ"
assert_reason_lacks "simplify block does not mention a rule file already read" "$out" "AGENTS.md"
for cmd in "npx lensdiff --merge-base HEAD origin/main" "FORCE_COLOR=0 lensdiff --merge-base HEAD origin/main" "git fetch && lensdiff ." "lensdiff --help --merge-base HEAD"; do
  out=$(run_bash "$cmd" "$t" "$agents_repo")
  assert_block_contains "[$cmd] is a lensdiff launch" "$out" "3. simplify と AI レビュー"
done
for cmd in "lensdiff --help" "lensdiff -h" "npx lensdiff --version" \
  "command -v lensdiff >/dev/null || npm install -g https://github.com/komtaki/lensdiff/releases/latest/download/lensdiff.tgz" \
  "[ -e ~/.claude/skills/lensdiff ] || npx skills add komtaki/lensdiff --skill lensdiff -g -a claude-code -y" \
  'git commit -m "fix: lensdiff の起動を直す"'; do
  out=$(run_bash "$cmd" "$t" "$agents_repo")
  assert_pass "[$cmd] is not gated" "$out"
done
out=$(run_bash "lensdiff --merge-base HEAD origin/main" "$t" "$agents_repo" "subagent")
assert_block_contains "lensdiff from a subagent blocks on simplify" "$out" "3. simplify と AI レビュー"

t=$(new_transcript)
add_skill "$t" "develop:ship"
out=$(run_bash "lensdiff ." "$t" "$agents_repo" "subagent")
assert_block_contains "lensdiff from a subagent without simplify and rule read blocks on simplify" "$out" "3. simplify と AI レビュー"
assert_block_contains "lensdiff from a subagent without simplify and rule read blocks on AGENTS.md" "$out" "AGENTS.md"
add_skill "$t" "simplify"
add_read "$t" "$agents_repo/AGENTS.md" true
out=$(run_bash "lensdiff ." "$t" "$agents_repo" "subagent")
assert_block_contains "AGENTS.md read on a sidechain does not count" "$out" "AGENTS.md"
add_read "$t" "$agents_repo/AGENTS.md"
out=$(run_bash "lensdiff ." "$t" "$agents_repo" "subagent")
assert_pass "lensdiff from a subagent passes after the main agent reads AGENTS.md" "$out"

t=$(new_transcript)
add_skill "$t" "develop:ship" "simplify"
out=$(run_bash "lensdiff --merge-base HEAD origin/main" "$t" "$agents_repo")
assert_block_contains "lensdiff before reading AGENTS.md blocks" "$out" "AGENTS.md"
assert_block_contains "rule block accepts Read" "$out" "Read"
assert_block_contains "rule block accepts Bash" "$out" "Bash"
assert_block_contains "rule block sends back to the inspection of step 2" "$out" "「2. 実装」の検品"
assert_block_contains "rule block points to inspection.md A and B" "$out" "inspection.md の A・B"
assert_block_contains "rule block restarts from step 3 after fixing the diff" "$out" "3 からやり直して"
assert_reason_lacks "rule block does not skip ahead to step 4" "$out" "4 に進み"
assert_block_contains "rule block asks to read it again after compact" "$out" "/compact"
assert_reason_lacks "rule block does not mention simplify once invoked" "$out" "3. simplify と AI レビュー"
out=$(run_bash "lensdiff --merge-base HEAD origin/main" "$t" "$agents_repo/sub")
assert_block_contains "rule file is looked up at the git top level of cwd" "$out" "AGENTS.md"
add_read "$t" "$agents_repo/CLAUDE.md"
out=$(run_bash "lensdiff --merge-base HEAD origin/main" "$t" "$agents_repo")
assert_block_contains "AGENTS.md is required even if CLAUDE.md was read" "$out" "AGENTS.md"
out=$(run_bash "cd $agents_repo && lensdiff --merge-base HEAD origin/main" "$t" "$bare_repo")
assert_block_contains "cd target decides the repository" "$out" "AGENTS.md"
out=$(run_bash "cd agents; lensdiff --merge-base HEAD origin/main" "$t" "$work_dir")
assert_block_contains "relative cd target is resolved from cwd" "$out" "AGENTS.md"
add_bash_read "$t" "grep -n foo $agents_repo/sub/../AGENTS.md.bak" "$work_dir"
out=$(run_bash "lensdiff ." "$t" "$agents_repo")
assert_block_contains "a similar path in a Bash command does not count" "$out" "AGENTS.md"
for cmd in "ls AGENTS.md" "test -f AGENTS.md && echo ok" "cat README.md; ls -l AGENTS.md" "echo AGENTS.md | wc -l"; do
  add_bash_read "$t" "$cmd" "$agents_repo"
  out=$(run_bash "lensdiff ." "$t" "$agents_repo")
  assert_block_contains "[$cmd] is not a read of AGENTS.md" "$out" "AGENTS.md"
done
add_read "$t" "$work_dir/agents-link/AGENTS.md"
out=$(run_bash "lensdiff --merge-base HEAD origin/main" "$t" "$agents_repo")
assert_pass "AGENTS.md read through a symlink counts" "$out"
out=$(run_bash "cd $agents_repo && lensdiff --merge-base HEAD origin/main" "$t" "$bare_repo")
assert_pass "cd target with AGENTS.md read passes" "$out"
out=$(run_bash "lensdiff --merge-base HEAD origin/main" "$t" "$bare_repo")
assert_pass "repository without AGENTS.md or CLAUDE.md passes" "$out"
out=$(run_bash "lensdiff --merge-base HEAD origin/main" "$t" "$claude_repo")
assert_block_contains "CLAUDE.md is required when there is no AGENTS.md" "$out" "CLAUDE.md"
add_bash_read "$t" "head -50 '$claude_repo/CLAUDE.md' | less" "$work_dir"
out=$(run_bash "lensdiff --merge-base HEAD origin/main" "$t" "$claude_repo")
assert_pass "lensdiff after reading CLAUDE.md with Bash passes" "$out"

t=$(new_transcript)
add_skill "$t" "develop:ship"
add_bash_read "$t" "cat \"$space_repo/AGENTS.md\"" "$work_dir"
add_skill "$t" "simplify"
out=$(run_bash "lensdiff ." "$t" "$space_repo")
assert_pass "quoted Bash read path with a space counts" "$out"

for cmd in "ls -la && cat AGENTS.md" "git status; rg -n ship AGENTS.md" "cat < AGENTS.md" "sed -n 1,20p AGENTS.md | nl"; do
  t=$(new_transcript)
  add_skill "$t" "develop:ship" "simplify"
  add_bash_read "$t" "$cmd" "$agents_repo"
  out=$(run_bash "lensdiff ." "$t" "$agents_repo")
  assert_pass "[$cmd] is a read of AGENTS.md" "$out"
done

t=$(new_transcript)
add_skill "$t" "develop:ship"
out=$(run_bash "lensdiff --merge-base HEAD origin/main" "$t" "$agents_repo")
assert_block_contains "both missing steps are reported: simplify" "$out" "3. simplify と AI レビュー"
assert_block_contains "both missing steps are reported: AGENTS.md" "$out" "AGENTS.md"

for skill in "ship" "develop:ship" "foo:ship"; do
  t=$(new_transcript)
  add_skill "$t" "$skill"
  out=$(run_agent "Agent" "$t")
  assert_block_contains "skill [$skill] starts the ship gates" "$out" "inspection.md"
done

for skill in "relationship" "develop:shipping"; do
  t=$(new_transcript)
  add_skill "$t" "$skill"
  out=$(run_agent "Agent" "$t")
  assert_pass "skill [$skill] does not start the ship gates" "$out"
done

for skill in "simplify" "develop:simplify"; do
  t=$(new_transcript)
  add_skill "$t" "develop:ship" "$skill"
  out=$(run_bash "lensdiff ." "$t" "$bare_repo")
  assert_pass "skill [$skill] unlocks lensdiff" "$out"
done

t=$(new_transcript)
add_skill "$t" "develop:ship" "oversimplify"
out=$(run_bash "lensdiff ." "$t" "$bare_repo")
assert_block_contains "skill [oversimplify] does not unlock lensdiff" "$out" "3. simplify と AI レビュー"

t=$(new_transcript)
add_skill "$t" "develop:ship"
add_command "$t" "/simplify"
out=$(run_bash "lensdiff ." "$t" "$bare_repo")
assert_pass "command [/simplify] unlocks lensdiff" "$out"

t=$(new_transcript)
add_skill "$t" "develop:ship"
for cmd in "git commit -F - <<'EOF'"$'\n'"fix: x"$'\n\n'"lensdiff で承認を得た"$'\n'"EOF" \
  "cat <<-EOF > note.md"$'\n'$'\t'"lensdiff --merge-base HEAD"$'\n'$'\t'"EOF" \
  "git commit -m \"fix: x"$'\n\n'"lensdiff で承認を得た\"" \
  "echo 'a"$'\n'"lensdiff .'"; do
  out=$(run_bash "$cmd" "$t" "$agents_repo")
  assert_pass "[$cmd] heredoc or quoted lines are not launches" "$out"
done
out=$(run_bash "cat <<'EOF'"$'\n'"x"$'\n'"EOF"$'\n'"lensdiff --merge-base HEAD origin/main" "$t" "$agents_repo")
assert_block_contains "lensdiff after a heredoc is a launch" "$out" "3. simplify と AI レビュー"
for cmd in "npx -y lensdiff ." "npx lensdiff@latest ." "bunx lensdiff ." "env FOO=1 lensdiff ." \
  "/opt/homebrew/bin/lensdiff ." "nohup lensdiff . &" "if true; then lensdiff .; fi" "(cd $agents_repo && lensdiff .)" \
  "timeout 600 lensdiff ." "timeout -k 5 -s KILL 600 lensdiff ." "command lensdiff ." "nice lensdiff ." "nice -n 10 lensdiff ." \
  "npm exec lensdiff ." "npm exec -- lensdiff ." "npm exec --yes -- lensdiff ." "pnpm dlx lensdiff ."; do
  out=$(run_bash "$cmd" "$t" "$agents_repo")
  assert_block_contains "[$cmd] is a lensdiff launch" "$out" "3. simplify と AI レビュー"
done
out=$(run_bash "lensdiff 'unclosed" "$t" "$agents_repo")
assert_block_contains "unparsable lensdiff command blocks" "$out" "引用符を閉じて"

t=$(new_transcript)
add_skill "$t" "develop:ship" "simplify"
out=$(run_bash "cd $agents_repo/sub && lensdiff ." "$t" "$bare_repo")
assert_block_contains "cd target is resolved to its git top level" "$out" "$agents_repo/AGENTS.md"
out=$(run_bash "cd \"$space_repo\" && lensdiff ." "$t" "$bare_repo")
assert_block_contains "quoted cd target with a space is resolved" "$out" "$space_repo/AGENTS.md"
out=$(run_bash "(cd agents && lensdiff .)" "$t" "$work_dir")
assert_block_contains "cd in a subshell decides the repository" "$out" "$agents_repo/AGENTS.md"
out=$(run_bash "cd $plain_dir && lensdiff ." "$t" "$bare_repo")
assert_block_contains "cd target outside git is used as is" "$out" "$plain_dir/AGENTS.md"
out=$(run_bash "pushd $agents_repo/sub && lensdiff ." "$t" "$bare_repo")
assert_block_contains "pushd target decides the repository" "$out" "$agents_repo/AGENTS.md"
out=$(run_bash "cd \$REPO && lensdiff ." "$t" "$bare_repo")
assert_block_contains "unresolvable cd target blocks" "$out" "cd を挟まず"

for read_name in CLAUDE.md AGENTS.md; do
  t=$(new_transcript)
  add_skill "$t" "develop:ship" "simplify"
  add_read "$t" "$linked_repo/$read_name"
  out=$(run_bash "lensdiff ." "$t" "$linked_repo")
  assert_pass "AGENTS.md linked to CLAUDE.md passes after reading $read_name" "$out"
done

t=$(new_transcript)
add_skill "$t" "develop:ship" "simplify"
python3 - "$t" "$work_dir" <<'EOF'
import json, sys
transcript, work_dir = sys.argv[1], sys.argv[2]
blob = "x" * 20000
with open(transcript, "a") as out:
    for i in range(400):
        out.write(json.dumps({"type": "user", "isSidechain": False, "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "toolu_%d" % i, "content": "AGENTS.md develop:ship " + blob}]}}) + "\n")
        out.write(json.dumps({"type": "assistant", "isSidechain": False, "cwd": work_dir, "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "toolu_%d" % i, "name": "Bash", "input": {"command": "grep -rn ship %s/dir-%d/AGENTS.md" % (work_dir, i)}}]}}) + "\n")
    for i in range(30000):
        out.write(json.dumps({"type": "assistant", "isSidechain": False, "cwd": work_dir, "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "toolu_r%d" % i, "name": "Read", "input": {"file_path": "%s/dir-%d/file-%d.md" % (work_dir, i, i)}}]}}) + "\n")
EOF
add_read "$t" "$agents_repo/AGENTS.md"
size=$(wc -c < "$t" | tr -d ' ')
started=$(now)
out=$(run_bash "lensdiff --merge-base HEAD origin/main" "$t" "$agents_repo")
elapsed=$(python3 -c 'import sys; print(round(float(sys.argv[2]) - float(sys.argv[1]), 3))' "$started" "$(now)")
assert_pass "lensdiff with a large transcript passes" "$out"
if [ "$size" -ge 10000000 ] && python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) < 3 else 1)' "$elapsed"; then
  echo "PASS: a $size byte transcript is checked in under 3 seconds ($elapsed s)"
else
  echo "FAIL: a $size byte transcript (>= 10000000) is checked in under 3 seconds ($elapsed s)"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "All tests passed"
