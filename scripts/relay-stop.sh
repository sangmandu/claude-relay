#!/usr/bin/env bash
# Stop Hook for claude-relay
# Called by Claude Code when the session is about to stop.
# Reads JSON from stdin, checks for pending tasks in checkpoint files.
# Output: JSON {"decision":"block","reason":"..."} to prevent stop, or exit 0 to allow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKPOINT_PY="${SCRIPT_DIR}/checkpoint.py"

input=$(cat)

stop_hook_active=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('stop_hook_active',''))" 2>/dev/null || echo "")
if [[ "$stop_hook_active" == "true" ]]; then
    exit 0
fi

cwd=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null || echo "")
if [[ -z "$cwd" ]]; then
    cwd="$(pwd)"
fi

checkpoints=()
for f in "$cwd"/checkpoint*.yaml; do
    [[ -f "$f" ]] && checkpoints+=("$f")
done

if [[ ${#checkpoints[@]} -eq 0 ]]; then
    exit 0
fi

for ckpt in "${checkpoints[@]}"; do
    if python3 "$CHECKPOINT_PY" -f "$ckpt" has_pending 2>/dev/null; then
        next_task=$(python3 "$CHECKPOINT_PY" -f "$ckpt" get_ready_tasks 2>/dev/null || echo "[]")
        first_id=$(echo "$next_task" | python3 -c "import sys,json; ids=json.load(sys.stdin); print(ids[0] if ids else '')" 2>/dev/null || echo "")

        if [[ -n "$first_id" ]]; then
            title=$(python3 "$CHECKPOINT_PY" -f "$ckpt" get_task_field "$first_id" title 2>/dev/null || echo "$first_id")
            reason="다음: ${title} ($(basename "$ckpt"))"
        else
            reason="pending tasks remain in $(basename "$ckpt")"
        fi

        echo "{\"decision\":\"block\",\"reason\":\"${reason}\"}"
        exit 0
    fi
done

exit 0
