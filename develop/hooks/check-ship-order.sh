#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // ""')
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""')

block() {
  printf '%s' "$1" | jq -Rs '{decision: "block", reason: .}'
  exit 0
}

# 出力は 1 行目が状態（missing / denied / unreadable / ok）、2 行目以降が ship・simplify・inspection・rule のうち満たしたもの
scan_transcript() {
  python3 -c '
import json, os, re, shlex, sys

transcript, rule_file = sys.argv[1], sys.argv[2]
if not transcript or not os.path.isfile(transcript):
    print("missing")
    sys.exit(0)

INSPECTION_SUFFIX = "/skills/ship/inspection.md"
rule_real = os.path.realpath(rule_file) if rule_file else ""
rule_names = {os.path.basename(rule_file), os.path.basename(rule_real)} if rule_file else set()
read_needles = [b"inspection.md"] + [name.encode() for name in rule_names]
COMMAND_NAME = re.compile(r"<command-name>/([^<\s]+)</command-name>")
VARIABLE = re.compile(r"\$\{(\w+)\}|\$(\w+)")
ASSIGNMENT = re.compile(r"^([A-Za-z_]\w*)=(.*)$", re.S)
RAW_SKILL_SHIP = re.compile(rb"\"skill\"\s*:\s*\"(?:[^\"]*:)?ship\"")
RAW_COMMAND_SHIP = re.compile(rb"<command-name>/(?:[^<:]*:)?ship</command-name>")
RAW_USER = re.compile(rb"\"type\"\s*:\s*\"user\"")
READERS = {"cat", "head", "tail", "sed", "less", "more", "bat", "nl", "awk", "grep", "rg", "view"}

def skill_kind(name):
    base = name.rsplit(":", 1)[-1]
    return base if base in ("ship", "simplify") else None

def resolve(path, base):
    if not path or "$" in path or "`" in path:
        return None
    path = os.path.expanduser(path)
    if not os.path.isabs(path):
        if not base:
            return None
        path = os.path.join(base, path)
    return os.path.normpath(path)

def matches(path):
    found = set()
    if path is None:
        return found
    if path.endswith(INSPECTION_SUFFIX) or os.path.realpath(path).endswith(INSPECTION_SUFFIX):
        found.add("inspection")
    if rule_real and os.path.basename(path) in rule_names and os.path.realpath(path) == rule_real:
        found.add("rule")
    return found

def expand(token, variables):
    return VARIABLE.sub(lambda m: variables.get(m.group(1) or m.group(2), m.group(0)), token)

def bash_reads(command, cwd):
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()<>")
    lexer.whitespace_split = True
    try:
        tokens = list(lexer)
    except ValueError:
        tokens = command.split()
    found = set()
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
        if reading and ("inspection.md" in token or any(name in token for name in rule_names)):
            found |= matches(resolve(token.split("=", 1)[-1] if token.startswith("-") else token, base))
    return found

invoked = set()
reads = set()
structured = False
raw_ship = False
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
            if is_tool_use and not (is_compact or is_command) and b"\"Skill\"" not in line and not any(needle in line for needle in read_needles):
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
                reads.clear()
            elif entry.get("type") == "user":
                texts = [content] if isinstance(content, str) else [part.get("text") or "" for part in content or [] if isinstance(part, dict) and part.get("type") == "text"]
                for text in texts:
                    for name in COMMAND_NAME.findall(text):
                        structured = True
                        kind = skill_kind(name)
                        if kind:
                            invoked.add(kind)
            elif entry.get("type") == "assistant" and isinstance(content, list):
                for part in content:
                    if not isinstance(part, dict) or part.get("type") != "tool_use" or not isinstance(part.get("input"), dict):
                        continue
                    tool, tool_input = part.get("name"), part["input"]
                    if tool == "Skill" and isinstance(tool_input.get("skill"), str):
                        structured = True
                        kind = skill_kind(tool_input["skill"])
                        if kind:
                            invoked.add(kind)
                    elif tool == "Read" and isinstance(tool_input.get("file_path"), str):
                        reads |= matches(resolve(tool_input["file_path"], entry.get("cwd")))
                    elif tool == "Bash" and isinstance(tool_input.get("command"), str):
                        reads |= bash_reads(tool_input["command"], entry.get("cwd"))
except OSError:
    print("denied")
    sys.exit(0)

print("unreadable" if raw_ship and not structured else "ok")
for flag in sorted(invoked | reads):
    print(flag)
' "$TRANSCRIPT_PATH" "${1:-}"
}

transcript_state() {
  printf '%s\n' "$SCAN" | sed -n 1p
}

transcript_has() {
  printf '%s\n' "$SCAN" | sed 1d | grep -qx "$1"
}

DENIED_REASON="transcript を開けない・読めないため、develop:ship の手順を守っているかを判定できません。hook 入力の transcript_path（${TRANSCRIPT_PATH}）の権限を確かめ、止めてユーザーに伝えてください。"
UNREADABLE_REASON="transcript の形式が読めないため、develop:ship の手順を守っているかを判定できません。hook 入力の transcript_path（${TRANSCRIPT_PATH}）の形式が変わった可能性があります。止めてユーザーに伝え、check-ship-order.sh を直してもらってください。"

if [ "$TOOL_NAME" = "Agent" ] || [ "$TOOL_NAME" = "Task" ]; then
  [ -z "$AGENT_ID" ] || exit 0
  SCAN=$(scan_transcript)
  case "$(transcript_state)" in
    missing) exit 0 ;;
    denied) block "$DENIED_REASON" ;;
    unreadable) block "$UNREADABLE_REASON" ;;
  esac
  transcript_has ship || exit 0
  if ! transcript_has inspection; then
    block "サブエージェントに依頼する前に、develop:ship の inspection.md をメインエージェントが開いてください（Read でも、Bash の cat などでも構いません）。依頼が inspection.md の節（A〜D）に当たるなら、その節の「作り手が返す根拠」を完了条件として依頼文に入れ、「メインエージェントが見る観点」をタスクリストに写してから依頼します。/compact の後は会話から中身が消えるため、読み直してください。"
  fi
  exit 0
fi

[ "$TOOL_NAME" = "Bash" ] || exit 0

lensdiff_launch_dir() {
  printf '%s' "$INPUT" | python3 -c '
import json, os, re, shlex, sys

data = json.load(sys.stdin)
command = data["tool_input"].get("command") or ""
cwd = data.get("cwd") or os.getcwd()

heredoc = re.compile(r"(?<!<)<<(-?)[ \t]*([\"\x27]?)([A-Za-z0-9_]+)\2")
lines = []
delimiters = []
for line in command.replace("\\\n", "").split("\n"):
    if delimiters:
        strip_tabs, delimiter = delimiters[0]
        if (line.lstrip("\t") if strip_tabs else line) == delimiter:
            delimiters.pop(0)
        continue
    lines.append(line)
    delimiters = [(m.group(1) == "-", m.group(3)) for m in heredoc.finditer(line)]

lexer = shlex.shlex(";".join(lines), posix=True, punctuation_chars=";&|()")
lexer.whitespace_split = True
try:
    tokens = list(lexer)
except ValueError:
    if "lensdiff" in command:
        print("unparsable")
    sys.exit(0)

def is_separator(token):
    return set(token) <= set(";&|()")

COMMAND_KEYWORDS = {"if", "then", "else", "elif", "do", "while", "until", "!", "{", "time"}
WRAPPER_OPTIONS_WITH_VALUE = {
    "env": {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"},
    "nohup": set(),
    "exec": {"-a"},
    "time": set(),
    "nice": {"-n", "--adjustment"},
    "timeout": {"-k", "--kill-after", "-s", "--signal"},
    "command": set(),
}
RUNNERS = [["npx"], ["bunx"], ["pnpx"], ["npm", "exec"], ["npm", "x"], ["pnpm", "dlx"], ["pnpm", "exec"], ["yarn", "dlx"]]
HELP_ONLY = {"--help", "-h", "--version"}

def is_assignment(token):
    return re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", token) is not None

def resolve(path, base):
    if path is None or "$" in path or "`" in path or path == "-":
        return None
    path = os.path.expanduser(path)
    return path if os.path.isabs(path) else os.path.join(base, path)

def command_words(words):
    while words and (is_assignment(words[0]) or words[0] in WRAPPER_OPTIONS_WITH_VALUE):
        wrapper = words[0]
        words = words[1:]
        if wrapper == "command" and words[:1] in (["-v"], ["-V"]):
            return []
        options_with_value = WRAPPER_OPTIONS_WITH_VALUE.get(wrapper, set())
        while words and words[0].startswith("-"):
            words = words[2:] if words[0] in options_with_value else words[1:]
        if wrapper == "timeout":
            words = words[1:]
    for runner in RUNNERS:
        if words[:len(runner)] == runner:
            words = words[len(runner):]
            while words and words[0].startswith("-"):
                words = words[1:]
            if words and not words[0].startswith("@"):
                words = [words[0].split("@")[0]] + words[1:]
            break
    return words

current_dir = cwd
at_command = True
i = 0
while i < len(tokens):
    token = tokens[i]
    if is_separator(token) or token in COMMAND_KEYWORDS and at_command:
        at_command = True
        i += 1
        continue
    if not at_command:
        i += 1
        continue
    at_command = False
    end = i
    while end < len(tokens) and not is_separator(tokens[end]):
        end += 1
    words = command_words(tokens[i:end])
    if words and words[0] in ("cd", "pushd"):
        current_dir = resolve(words[1] if len(words) > 1 else None, current_dir or cwd)
    elif words and os.path.basename(words[0]) == "lensdiff":
        args = words[1:]
        if not (args and set(args) <= HELP_ONLY):
            print("launch\t" + (current_dir or ""))
            sys.exit(0)
    i = end
'
}

LAUNCH=$(lensdiff_launch_dir)
if [ -z "$LAUNCH" ]; then
  exit 0
fi

rule_file=""
launch_dir=""
if [ "$LAUNCH" != "unparsable" ]; then
  launch_dir="${LAUNCH#*$'\t'}"
fi
if [ -n "$launch_dir" ]; then
  repo_dir=$(git -C "$launch_dir" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$launch_dir")
  if [ -f "$repo_dir/AGENTS.md" ]; then
    rule_file="$repo_dir/AGENTS.md"
  elif [ -f "$repo_dir/CLAUDE.md" ]; then
    rule_file="$repo_dir/CLAUDE.md"
  fi
fi

SCAN=$(scan_transcript "$rule_file")
case "$(transcript_state)" in
  missing) exit 0 ;;
  denied) block "$DENIED_REASON" ;;
  unreadable) block "$UNREADABLE_REASON" ;;
esac
transcript_has ship || exit 0

if [ "$LAUNCH" = "unparsable" ]; then
  block "コマンドを解析できないため、lensdiff の起動かどうかを判定できません。引用符を閉じて実行し直してください。"
fi

reasons=()

if ! transcript_has simplify; then
  reasons+=("lensdiff の前に「3. simplify と AI レビュー」を回してください。差分の規模で省かない。省きたいときは止めてユーザーに聞く。止められたら 3 の頭から回し、hook を通すことを目的に simplify だけを起動しないでください。")
fi

if [ -z "$launch_dir" ]; then
  reasons+=("cd の行き先を解決できないため、対象リポジトリを判定できません。cd を挟まず、リポジトリ直下を作業ディレクトリにして lensdiff を起動してください。")
elif [ -n "$rule_file" ] && ! transcript_has rule; then
  reasons+=("lensdiff の前に、「2. 実装」の検品に戻ってください。差分が従う規約 ${rule_file} をメインエージェントが開き（Read でも、Bash の cat などでも構いません）、差分の該当箇所と照らします（inspection.md の A・B の「作り手が返す根拠」と「メインエージェントが見る観点」）。照合で差分を直したら 3 からやり直してください。セッション開始時に自動で読み込まれたものは数えません。/compact の後は会話から中身が消えるため、読み直してください。")
fi

if [ "${#reasons[@]}" -gt 0 ]; then
  block "$(printf '%s\n' "${reasons[@]}")"
fi
