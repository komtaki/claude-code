#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
FIELDS=$(printf '%s' "$INPUT" | jq -j '[.agent_id // "", .tool_name // "", .transcript_path // ""] | map(tostring) | join("\u001f")')
# タブは IFS の空白扱いで連続した空値が詰まり、@tsv は \ を書き換えるため、空白でない区切りで分ける
IFS=$'\x1f' read -r -d '' AGENT_ID TOOL_NAME TRANSCRIPT_PATH < <(printf '%s' "$FIELDS") || true

block() {
  printf '%s' "$1" | jq -Rs '{decision: "block", reason: .}'
  exit 0
}

# 出力は 1 行で、先頭が状態（missing / denied / unreadable / ok）、続けて ship・inspection のうち満たしたものを空白区切りで並べる
scan_transcript() {
  python3 -c '
import json, os, re, shlex, sys

transcript = sys.argv[1]
if not transcript or not os.path.isfile(transcript):
    print("missing")
    sys.exit(0)

INSPECTION_SUFFIX = "/skills/ship/inspection.md"
COMMAND_NAME = re.compile(r"<command-name>/([^<\s]+)</command-name>")
VARIABLE = re.compile(r"\$\{(\w+)\}|\$(\w+)")
ASSIGNMENT = re.compile(r"^([A-Za-z_]\w*)=(.*)$", re.S)
RAW_SKILL_SHIP = re.compile(rb"\"skill\"\s*:\s*\"(?:[^\"]*:)?ship\"")
RAW_COMMAND_SHIP = re.compile(rb"<command-name>/(?:[^<:]*:)?ship</command-name>")
RAW_USER = re.compile(rb"\"type\"\s*:\s*\"user\"")
READERS = {"cat", "head", "tail", "sed", "less", "more", "bat", "nl", "awk", "grep", "rg", "view"}

def resolve(path, base):
    if not path or "$" in path or "`" in path:
        return None
    path = os.path.expanduser(path)
    if not os.path.isabs(path):
        if not base:
            return None
        path = os.path.join(base, path)
    return os.path.normpath(path)

def is_inspection(path):
    return path is not None and (path.endswith(INSPECTION_SUFFIX) or os.path.realpath(path).endswith(INSPECTION_SUFFIX))

def expand(token, variables):
    return VARIABLE.sub(lambda m: variables.get(m.group(1) or m.group(2), m.group(0)), token)

def bash_reads(command, cwd):
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()<>")
    lexer.whitespace_split = True
    try:
        tokens = list(lexer)
    except ValueError:
        tokens = command.split()
    base = cwd
    variables = {}
    at_command = True
    reading = False
    for i, token in enumerate(tokens):
        if set(token) <= set("<>"):
            reading = reading and token == "<"
            continue
        if set(token) <= set(";&|()"):
            at_command = True
            continue
        token = expand(token, variables)
        assignment = ASSIGNMENT.match(token)
        if at_command and assignment:
            variables[assignment.group(1)] = assignment.group(2)
            continue
        if at_command:
            if token in ("cd", "pushd") and i + 1 < len(tokens):
                base = resolve(expand(tokens[i + 1], variables), base)
            reading = os.path.basename(token) in READERS
            at_command = False
            continue
        if reading and "inspection.md" in token and is_inspection(resolve(token.split("=", 1)[-1] if token.startswith("-") else token, base)):
            return True
    return False

ship = False
inspection = False
structured = False
raw_ship = False

def record_skill(name):
    global structured, ship
    structured = True
    if name.rsplit(":", 1)[-1] == "ship":
        ship = True

try:
    with open(transcript, "rb") as lines:
        for line in lines:
            is_compact = b"compact_boundary" in line
            is_command = b"<command-name>" in line
            is_tool_use = b"\"tool_use\"" in line
            # <command-name> は JSON 中でエスケープされず tool_result やアシスタントの文にも現れるため、ユーザーの入力行だけを見る
            if not raw_ship and (
                b"\"skill\"" in line and RAW_SKILL_SHIP.search(line)
                or is_command and b"\"tool_result\"" not in line and RAW_USER.search(line) and RAW_COMMAND_SHIP.search(line)
            ):
                raw_ship = True
            if not (is_compact or is_command or is_tool_use):
                continue
            # 読んだかどうかは対象の名前を含む行だけが変えうるため、それ以外の tool_use 行は JSON として読まない
            if is_tool_use and not (is_compact or is_command) and b"\"Skill\"" not in line and b"inspection.md" not in line:
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if not isinstance(entry, dict) or entry.get("isSidechain") is True:
                continue
            message = entry.get("message") if isinstance(entry.get("message"), dict) else {}
            content = message.get("content")
            if entry.get("type") == "system" and entry.get("subtype") == "compact_boundary":
                inspection = False
            elif entry.get("type") == "user":
                texts = [content] if isinstance(content, str) else [part.get("text") or "" for part in content or [] if isinstance(part, dict) and part.get("type") == "text"]
                for text in texts:
                    for name in COMMAND_NAME.findall(text):
                        record_skill(name)
            elif entry.get("type") == "assistant" and isinstance(content, list):
                for part in content:
                    if not isinstance(part, dict) or part.get("type") != "tool_use" or not isinstance(part.get("input"), dict):
                        continue
                    tool, tool_input = part.get("name"), part["input"]
                    if tool == "Skill" and isinstance(tool_input.get("skill"), str):
                        record_skill(tool_input["skill"])
                    elif tool == "Read" and isinstance(tool_input.get("file_path"), str):
                        inspection = inspection or is_inspection(resolve(tool_input["file_path"], entry.get("cwd")))
                    elif tool == "Bash" and isinstance(tool_input.get("command"), str):
                        inspection = inspection or bash_reads(tool_input["command"], entry.get("cwd"))
except OSError:
    print("denied")
    sys.exit(0)

print(" ".join(["unreadable" if raw_ship and not structured else "ok"] + ["ship"] * ship + ["inspection"] * inspection))
' "$TRANSCRIPT_PATH"
}

transcript_has() {
  [[ " $TRANSCRIPT_FLAGS " == *" $1 "* ]]
}

DENIED_REASON="transcript を開けない・読めないため、develop:ship の手順を守っているかを判定できません。hook 入力の transcript_path（${TRANSCRIPT_PATH}）の権限を確かめ、止めてユーザーに伝えてください。"
UNREADABLE_REASON="transcript の形式が読めないため、develop:ship の手順を守っているかを判定できません。hook 入力の transcript_path（${TRANSCRIPT_PATH}）の形式が変わった可能性があります。止めてユーザーに伝え、check-ship-order.sh を直してもらってください。"

exit_unless_ship_session() {
  [ -f "$TRANSCRIPT_PATH" ] || exit 0
  [ -r "$TRANSCRIPT_PATH" ] || block "$DENIED_REASON"
  # ship の起動は Skill の値か <command-name> の末尾が ship になるため、どちらの生文字列もなければ python を起動せずに通す
  local status=0
  grep -qE 'ship("|</command-name>)' "$TRANSCRIPT_PATH" || status=$?
  [ "$status" -ne 1 ] || exit 0
  local scan state
  scan=$(scan_transcript)
  read -r state TRANSCRIPT_FLAGS <<<"$scan"
  case "$state" in
    missing) exit 0 ;;
    denied) block "$DENIED_REASON" ;;
    unreadable) block "$UNREADABLE_REASON" ;;
  esac
  transcript_has ship || exit 0
}

[ "$TOOL_NAME" = "Agent" ] || [ "$TOOL_NAME" = "Task" ] || exit 0
[ -z "$AGENT_ID" ] || exit 0
exit_unless_ship_session
if ! transcript_has inspection; then
  block "サブエージェントに依頼する前に、develop:ship の inspection.md をメインエージェントが開いてください（Read でも、Bash の cat などでも構いません）。依頼が inspection.md の節（A〜D）に当たるなら、その節の「作り手が返す根拠」を完了条件として依頼文に入れ、「メインエージェントが見る観点」をタスクリストに写してから依頼します。/compact の後は会話から中身が消えるため、読み直してください。"
fi
