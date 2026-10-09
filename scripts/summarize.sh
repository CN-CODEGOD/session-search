#!/bin/bash
# Session Gist Generator — compress session transcript to concise gist
# Uses dre's llama3.1-8B (Cloudflare Workers, free, ~1s response)
#
# Usage:
#   ./summarize.sh "transcript text"
#   echo "transcript" | ./summarize.sh
#   ./summarize.sh -f transcript.txt
#   ./summarize.sh -f transcript.txt -o gist.txt

BASE_URL="https://cj2api.***.workers.dev/v1"
API_KEY="test"
MODEL="llama3.1-8B"

SYSTEM_PROMPT="你是会话压缩专家。将会话内容压缩为简洁gist。要求：中文输出；保留主题、决策、结论、关键数据、人名、文件路径、技术方案；删除闲聊和重复；要点列表不超过12条；每条一句话。"

OUTPUT=""
INPUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f) INPUT_FILE="$2"; shift 2 ;;
        -o) OUTPUT="$2"; shift 2 ;;
        *)  INPUT="$1"; shift ;;
    esac
done

# Read from file if specified
if [ -n "$INPUT_FILE" ]; then
    INPUT=$(cat "$INPUT_FILE")
fi

# Read from stdin if no input yet
if [ -z "$INPUT" ]; then
    INPUT=$(cat)
fi

if [ -z "$INPUT" ]; then
    echo "Error: empty input" >&2
    echo "Usage: $0 \"text\" | -f file [-o output]" >&2
    exit 1
fi

# Truncate to ~6000 chars (llama3.1-8B has 8K context, leave room for system+response)
INPUT="${INPUT:0:6000}"

# Escape for JSON
INPUT_ESCAPED=$(echo "$INPUT" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))")

RESPONSE=$(curl -s -X POST "${BASE_URL}/chat/completions" \
    -H "Authorization: Bearer ***}" \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"${MODEL}\",
        \"messages\": [
            {\"role\": \"system\", \"content\": ${SYSTEM_PROMPT@Q}},
            {\"role\": \"user\", \"content\": ${INPUT_ESCAPED}}
        ],
        \"max_tokens\": 512,
        \"temperature\": 0.3
    }")

GIST=$(echo "$RESPONSE" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['choices'][0]['message']['content'])
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
")

if [ -n "$OUTPUT" ]; then
    echo "$GIST" > "$OUTPUT"
else
    echo "$GIST"
fi
