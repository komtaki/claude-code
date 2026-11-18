#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check="$script_dir/../check-ship-order.sh"

failures=0
test_counter=0

export TMPDIR="${TMPDIR:-/tmp}"
work_dir=$(cd "$(mktemp -d "$TMPDIR/check-ship-order-test.XXXXXX")" && pwd -P)
trap 'rm -rf "$work_dir"' EXIT

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
  jq -n --arg cmd "$1" --arg t "$2" \
    '{tool_name:"Bash", tool_input:{command:$cmd}, session_id:"s", cwd:"/", transcript_path:$t}' | bash "$check"
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

out=$(run_agent "Agent" "$work_dir/missing.jsonl")
assert_pass "Agent with a missing transcript passes" "$out"
out=$(jq -n '{tool_name:"Agent", tool_input:{prompt:"x"}, session_id:"s"}' | bash "$check")
assert_pass "Agent without transcript_path passes" "$out"

t=$(new_transcript)
printf '%s\n' '{"kind":"turn","role":"assistant","calls":[{"tool":"Skill","args":{"skill":"develop:ship"}}]}' >> "$t"
out=$(run_agent "Agent" "$t")
assert_block_contains "unreadable transcript with a ship invocation blocks Agent" "$out" "transcript の形式が読めない"
out=$(run_bash "lensdiff ." "$t")
assert_pass "unreadable transcript does not block Bash" "$out"

t=$(new_transcript)
printf '%s\n' '{"type":"user","payload":"<command-name>/develop:ship</command-name>"}' >> "$t"
out=$(run_agent "Agent" "$t")
assert_block_contains "unreadable user line with a ship command blocks Agent" "$out" "transcript の形式が読めない"

t=$(new_transcript)
jq -cn '{type:"user", isSidechain:false, message:{role:"user", content:[{type:"tool_result", tool_use_id:"toolu_x", content:"<command-name>/develop:ship</command-name>"}]}}' >> "$t"
jq -cn '{type:"assistant", isSidechain:false, message:{role:"assistant", content:[{type:"text", text:"<command-name>/develop:ship</command-name>"}]}}' >> "$t"
out=$(run_agent "Agent" "$t")
assert_pass "ship command text in a tool_result or assistant text does not block Agent" "$out"

t=$(new_transcript)
add_skill "$t" "develop:ship"
chmod 000 "$t"
out=$(run_agent "Agent" "$t")
assert_block_contains "transcript that cannot be opened blocks Agent" "$out" "transcript を開けない"
out=$(run_bash "lensdiff ." "$t")
assert_pass "transcript that cannot be opened does not block Bash" "$out"
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
add_bash_read "$t" "cd $work_dir/plugin/skills && sed -n 1,80p ship/inspection.md" "$work_dir/elsewhere"
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
add_skill "$t" "develop:ship"
add_compact "$t"
out=$(run_agent "Agent" "$t")
assert_block_contains "ship invoked before compact still starts the ship gates" "$out" "inspection.md"


t=$(new_transcript)
add_skill "$t" "develop:ship"
add_read "$t" "$inspection"
add_compact "$t"
add_compact "$t"
out=$(run_agent "Agent" "$t")
assert_block_contains "after two compacts Agent blocks until inspection.md is read again" "$out" "inspection.md"

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

t=$(new_transcript)
add_skill "$t" "develop:ship"
python3 - "$t" "$work_dir" <<'EOF'
import json, sys
transcript, work_dir = sys.argv[1], sys.argv[2]
blob = "x" * 20000
with open(transcript, "a") as out:
    for i in range(400):
        out.write(json.dumps({"type": "user", "isSidechain": False, "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "toolu_%d" % i, "content": "inspection.md develop:ship " + blob}]}}) + "\n")
        out.write(json.dumps({"type": "assistant", "isSidechain": False, "cwd": work_dir, "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "toolu_%d" % i, "name": "Bash", "input": {"command": "grep -rn ship %s/dir-%d/inspection.md" % (work_dir, i)}}]}}) + "\n")
    for i in range(30000):
        out.write(json.dumps({"type": "assistant", "isSidechain": False, "cwd": work_dir, "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "toolu_r%d" % i, "name": "Read", "input": {"file_path": "%s/dir-%d/file-%d.md" % (work_dir, i, i)}}]}}) + "\n")
EOF
add_read "$t" "$inspection"
size=$(wc -c < "$t" | tr -d ' ')
started=$(now)
out=$(run_agent "Agent" "$t")
elapsed=$(python3 -c 'import sys; print(round(float(sys.argv[2]) - float(sys.argv[1]), 3))' "$started" "$(now)")
assert_pass "Agent with a large transcript passes" "$out"
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
