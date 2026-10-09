#!/bin/bash
# Search through cached gists with a user query.
# Collects all cached gists, sends them + query to llama3.1-8B for semantic matching.
#
# Usage:
#   ./search_gists.sh "搜索关键词"
#   ./search_gists.sh "搜索关键词" --top 5

BASE_URL="https://cj2api.***.workers.dev/v1"
API_KEY="***"
MODEL="llama3.1-8B"

CACHE_DIR="${HOME}/.openclaw/workspace/skills/session-search/cache"
INDEX_FILE="${CACHE_DIR}/index.json"
TOP=3

QUERY=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --top) TOP="$2"; shift 2 ;;
        *)     QUERY="$1"; shift ;;
    esac
done

if [ -z "$QUERY" ]; then
    echo "Usage: $0 \"search query\" [--top N]" >&2
    exit 1
fi

if [ ! -d "$CACHE_DIR" ] || [ ! -f "$INDEX_FILE" ]; then
    echo "No gists cached yet. Run summarization first." >&2
    exit 1
fi

# Build context from all cached gists
GISTS=$(python3 -c "
import json, os, sys

cache_dir = os.path.expanduser('~/.openclaw/workspace/skills/session-search/cache')
index_file = os.path.join(cache_dir, 'index.json')

with open(index_file) as f:
    index = json.load(f)

parts = []
for entry in index.get('sessions', []):
    key = entry['sessionKey']
    gist_file = os.path.join(cache_dir, entry['cacheFile'])
    if os.path.exists(gist_file):
        with open(gist_file) as gf:
            gist = gf.read().strip()
        label = entry.get('label', '') or key
        parts.append(f'--- Session: {label} (key: {key}) ---\n{gist}')

# Truncate total to ~5000 chars
combined = '\n\n'.join(parts)
print(combined[:5000])
")

if [ -z "$GISTS" ]; then
    echo "No gist content found." >&2
    exit 1
fi

# Build search prompt
SEARCH_PROMPT="你是会话搜索助手。根据用户的搜索关键词，从以下会话摘要中找出最相关的会话。
要求：
- 按相关性排序，最多返回 ${TOP} 个
- 对每个匹配给出：sessionKey、相关性评分(1-10)、匹配原因(一句话)
- 如果没有相关结果，说明没有匹配
- 用 JSON 数组格式输出：[{\"sessionKey\":\"...\",\"score\":8,\"reason\":\"...\"}]

搜索关键词：${QUERY}"

INPUT=$(printf "%s\n\n%s" "$SEARCH_PROMPT" "$GISTS")
INPUT_ESCAPED=$(echo "$INPUT" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))")

RESPONSE=$(curl -s -X POST "${BASE_URL}/chat/completions" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"${MODEL}\",
        \"messages\": [{\"role\": \"user\", \"content\": ${INPUT_ESCAPED}}],
        \"max_tokens\": 1024,
        \"temperature\": 0.2
    }")

echo "$RESPONSE" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['choices'][0]['message']['content'])
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
