#!/bin/bash
# Batch summarize: reads JSONL lines {sessionKey, text, label} → outputs JSONL {sessionKey, gist}
# Processes up to MAX sessions, skipping cached ones. Updates cache index.
#
# Usage: ./batch_summarize.sh < input.jsonl > output.jsonl
#   or:  ./batch_summarize.sh input.jsonl output.jsonl

CACHE_DIR="${HOME}/.openclaw/workspace/skills/session-search/cache"
INDEX_FILE="${CACHE_DIR}/index.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$CACHE_DIR"

INPUT_FILE="$1"
OUTPUT_FILE="$2"

exec 3<&0
[ -n "$INPUT_FILE" ] && exec 3<"$INPUT_FILE"
[ -n "$OUTPUT_FILE" ] && exec >"$OUTPUT_FILE"

COUNT=0
MAX=5

if [ ! -f "$INDEX_FILE" ]; then
    echo '{"sessions":[]}' > "$INDEX_FILE"
fi

while IFS= read -r line <&3; do
    [ -z "$line" ] && continue
    [ $COUNT -ge $MAX ] && break

    SESSION_KEY=***"$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('sessionKey',''))")
    [ -z "$SESSION_KEY" ] && continue

    CACHE_HASH=$(echo -n "$SESSION_KEY" | md5sum | cut -d' ' -f1)
    CACHE_FILE="${CACHE_HASH}.txt"
    CACHE_PATH="$CACHE_DIR/$CACHE_FILE"

    if [ -f "$CACHE_PATH" ]; then
        GIST=$(cat "$CACHE_PATH")
    else
        TEXT=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('text',''))")
        [ -z "$TEXT" ] && continue
        GIST=$(echo "$TEXT" | "$SCRIPT_DIR/summarize.sh")
        echo "$GIST" > "$CACHE_PATH"

        # Update index via heredoc to avoid quoting hell
        python3 <<PYEOF
import json, os
idx_path = "$INDEX_FILE"
with open(idx_path) as f:
    idx = json.load(f)
existing = {e['sessionKey'] for e in idx['sessions']}
if "$SESSION_KEY" not in existing:
    idx['sessions'].append({
        'sessionKey': "$SESSION_KEY",
        'cacheFile': "$CACHE_FILE",
        'label': """$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('label',''))")"""
    })
with open(idx_path, 'w') as f:
    json.dump(idx, f, ensure_ascii=False)
PYEOF
    fi

    # Output result — use python with file to avoid shell quoting
    TMPF=$(mktemp)
    echo "$GIST" > "$TMPF"
    python3 -c "
import json, sys
with open(sys.argv[2]) as f:
    gist = f.read().strip()
print(json.dumps({'sessionKey': sys.argv[1], 'gist': gist}, ensure_ascii=False))
" "$SESSION_KEY" "$TMPF"
    rm -f "$TMPF"

    COUNT=$((COUNT + 1))
done

exec 3<&-
