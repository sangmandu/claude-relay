#!/usr/bin/env bash
set -euo pipefail

CHECKPOINT_FILE="${CHECKPOINT_FILE:-checkpoint.yaml}"

if [[ ! -f "$CHECKPOINT_FILE" ]]; then
  exit 0
fi

LAST_MODIFIED=$(stat -f %m "$CHECKPOINT_FILE" 2>/dev/null || stat -c %Y "$CHECKPOINT_FILE" 2>/dev/null)
NOW=$(date +%s)
AGE=$(( NOW - LAST_MODIFIED ))

if (( AGE > 5 )); then
  exit 0
fi

if command -v python3 &>/dev/null; then
  python3 -c "
import yaml, sys
try:
    with open('$CHECKPOINT_FILE') as f:
        data = yaml.safe_load(f)
    if not isinstance(data, dict):
        print('CHECKPOINT GUARD: checkpoint.yaml root is not a mapping', file=sys.stderr)
        sys.exit(1)
    if 'meta' not in data:
        print('CHECKPOINT GUARD: missing \"meta\" key', file=sys.stderr)
        sys.exit(1)
    if 'tasks' not in data:
        print('CHECKPOINT GUARD: missing \"tasks\" key', file=sys.stderr)
        sys.exit(1)
    if not isinstance(data['tasks'], list):
        print('CHECKPOINT GUARD: \"tasks\" must be a list', file=sys.stderr)
        sys.exit(1)
    for i, task in enumerate(data['tasks']):
        if not isinstance(task, dict):
            print(f'CHECKPOINT GUARD: task[{i}] is not a mapping', file=sys.stderr)
            sys.exit(1)
        for key in ('id', 'title', 'status'):
            if key not in task:
                print(f'CHECKPOINT GUARD: task[{i}] missing required key \"{key}\"', file=sys.stderr)
                sys.exit(1)
        if task['status'] not in ('pending', 'in_progress', 'completed'):
            print(f'CHECKPOINT GUARD: task[{i}] has invalid status \"{task[\"status\"]}\"', file=sys.stderr)
            sys.exit(1)
except yaml.YAMLError as e:
    print(f'CHECKPOINT GUARD: invalid YAML: {e}', file=sys.stderr)
    sys.exit(1)
"
fi
