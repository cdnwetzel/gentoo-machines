#!/bin/bash
# verify-llm.sh — thin HTTP wrapper for the XPS-9510 Ollama verifier
#
# Sends a payload to a small verifier model (default: qwen2.5:3b-instruct-q4_K_M)
# running on the XPS-9510 and returns a structured verdict. Built for the bigger
# AI nodes (T5810, 7960) to second-opinion their own outputs without spinning up
# anything heavy.
#
# Usage:
#   verify-llm.sh --task <task> [--criterion <text>] [--schema <file>] \
#                 [--payload <file>] [--model <name>] [--host <url>]
#
#   --task         one of: yes-no, fact-check, json-schema, judge, code-review
#   --criterion    judgment criterion (required for --task judge)
#   --schema       JSON schema file (required for --task json-schema)
#   --payload      file containing the content to verify (or read from stdin)
#   --model        override model (default: qwen2.5:3b-instruct-q4_K_M)
#   --host         override Ollama URL (default: $OLLAMA_HOST or xps-9510.lan:11434)
#
# Output (stdout): single-line JSON
#   {"verdict":"pass|fail","reasoning":"...","model":"...","ms":N}
#
# Exit codes:
#   0 = pass
#   1 = fail
#   2 = error (bad args, network, malformed response)

set -u

err()  { echo "verify-llm: $*" >&2; }
die()  { err "$*"; exit 2; }

need() { command -v "$1" &>/dev/null || die "missing dependency: $1"; }
need curl
need jq

MODEL="${VERIFY_LLM_MODEL:-qwen2.5:3b-instruct-q4_K_M}"
HOST_DEFAULT="${OLLAMA_HOST:-http://xps-9510.lan:11434}"
case "$HOST_DEFAULT" in
    http*) HOST="$HOST_DEFAULT" ;;
    *)     HOST="http://$HOST_DEFAULT" ;;
esac

TASK=""
CRITERION=""
SCHEMA_FILE=""
PAYLOAD_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --task)      TASK="$2"; shift 2 ;;
        --criterion) CRITERION="$2"; shift 2 ;;
        --schema)    SCHEMA_FILE="$2"; shift 2 ;;
        --payload)   PAYLOAD_FILE="$2"; shift 2 ;;
        --model)     MODEL="$2"; shift 2 ;;
        --host)      HOST="$2"; shift 2 ;;
        -h|--help)   sed -n '2,30p' "$0"; exit 0 ;;
        *)           die "unknown arg: $1" ;;
    esac
done

[ -n "$TASK" ] || die "--task required"

# Payload: file or stdin
if [ -n "$PAYLOAD_FILE" ]; then
    [ -r "$PAYLOAD_FILE" ] || die "cannot read payload: $PAYLOAD_FILE"
    PAYLOAD=$(cat "$PAYLOAD_FILE")
elif [ ! -t 0 ]; then
    PAYLOAD=$(cat)
else
    die "no payload (give --payload <file> or pipe via stdin)"
fi

# Build the system+user prompt per task type
case "$TASK" in
    yes-no)
        SYSTEM='You are a strict binary verifier. Read the user message and reply with JSON only: {"verdict":"pass" or "fail","reasoning":"one sentence"}. "pass" means the statement/question resolves to yes/true. "fail" means no/false. No prose outside JSON.'
        USER="$PAYLOAD"
        ;;
    fact-check)
        SYSTEM='You are a factual claim verifier. Determine if the user message contains a factually correct statement. Reply with JSON only: {"verdict":"pass" or "fail","reasoning":"explain the factual error if fail, otherwise confirm"}. No prose outside JSON.'
        USER="$PAYLOAD"
        ;;
    json-schema)
        [ -n "$SCHEMA_FILE" ] || die "--schema required for json-schema task"
        [ -r "$SCHEMA_FILE" ] || die "cannot read schema: $SCHEMA_FILE"
        SCHEMA=$(cat "$SCHEMA_FILE")
        SYSTEM='You validate JSON documents against a JSON Schema. Reply with JSON only: {"verdict":"pass" or "fail","reasoning":"list specific schema violations if fail, otherwise confirm match"}. No prose outside JSON.'
        USER=$(printf 'SCHEMA:\n%s\n\nDOCUMENT:\n%s' "$SCHEMA" "$PAYLOAD")
        ;;
    judge)
        [ -n "$CRITERION" ] || die "--criterion required for judge task"
        SYSTEM='You are an LLM-as-judge. Evaluate the user-provided content against the stated criterion. Reply with JSON only: {"verdict":"pass" or "fail","reasoning":"one paragraph justifying the verdict"}. Be conservative — only pass if the criterion is clearly met. No prose outside JSON.'
        USER=$(printf 'CRITERION: %s\n\nCONTENT:\n%s' "$CRITERION" "$PAYLOAD")
        ;;
    code-review)
        SYSTEM='You are a code reviewer focused on correctness, security, and obvious bugs. Reply with JSON only: {"verdict":"pass" or "fail","reasoning":"list concrete issues if fail (file/line/concern), otherwise note the code looks correct"}. Pass only if you see no real issues. No prose outside JSON.'
        USER="$PAYLOAD"
        ;;
    *)
        die "unknown --task: $TASK (use: yes-no fact-check json-schema judge code-review)"
        ;;
esac

# Construct the request body
REQ=$(jq -n \
    --arg model "$MODEL" \
    --arg system "$SYSTEM" \
    --arg user "$USER" \
    '{
        model: $model,
        stream: false,
        format: "json",
        options: { temperature: 0.0, num_ctx: 8192 },
        messages: [
            { role: "system", content: $system },
            { role: "user",   content: $user }
        ]
    }')

T0=$(date +%s%3N)
RESP=$(curl -fsS --max-time 120 -X POST "$HOST/api/chat" \
    -H 'Content-Type: application/json' \
    -d "$REQ" 2>/dev/null) \
    || { err "request to $HOST failed"; exit 2; }
T1=$(date +%s%3N)
MS=$((T1 - T0))

CONTENT=$(echo "$RESP" | jq -r '.message.content // empty')
[ -n "$CONTENT" ] || { err "empty response from model: $RESP"; exit 2; }

# Model returns JSON-in-string; parse it
VERDICT=$(echo "$CONTENT" | jq -r '.verdict // empty' 2>/dev/null)
REASONING=$(echo "$CONTENT" | jq -r '.reasoning // empty' 2>/dev/null)

if [ -z "$VERDICT" ] || [ -z "$REASONING" ]; then
    err "model did not return well-formed JSON: $CONTENT"
    exit 2
fi

# Emit our wrapper JSON
jq -n \
    --arg v "$VERDICT" \
    --arg r "$REASONING" \
    --arg m "$MODEL" \
    --argjson ms "$MS" \
    '{verdict:$v, reasoning:$r, model:$m, ms:$ms}'

case "$VERDICT" in
    pass) exit 0 ;;
    fail) exit 1 ;;
    *)    err "unexpected verdict: $VERDICT"; exit 2 ;;
esac
