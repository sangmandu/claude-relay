#!/usr/bin/env bash
# Integration tests for relay-stop.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STOP_HOOK="${SCRIPT_DIR}/scripts/relay-stop.sh"
CHECKPOINT_PY="${SCRIPT_DIR}/scripts/checkpoint.py"

PASS=0
FAIL=0
TOTAL=4

tmpdir=$(mktemp -d)
trap "rm -rf $tmpdir" EXIT

run_test() {
    local name="$1"
    local expected_exit="$2"
    local expected_pattern="${3:-}"
    local input="$4"
    local test_cwd="$5"

    set +e
    output=$(echo "$input" | bash "$STOP_HOOK" 2>/dev/null)
    actual_exit=$?
    set -e

    local ok=true
    if [[ "$actual_exit" -ne "$expected_exit" ]]; then
        ok=false
    fi
    if [[ -n "$expected_pattern" ]] && ! echo "$output" | grep -q "$expected_pattern"; then
        ok=false
    fi

    if $ok; then
        echo "  ✅ $name"
        PASS=$((PASS + 1))
    else
        echo "  ❌ $name (exit=$actual_exit, expected=$expected_exit)"
        [[ -n "$output" ]] && echo "     output: $output"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Stop Hook Tests ==="

# Case 1: No checkpoint file → exit 0
test_cwd="$tmpdir/case1"
mkdir -p "$test_cwd"
run_test "Case 1: No checkpoint → allow stop" 0 "" "{\"cwd\":\"$test_cwd\"}" "$test_cwd"

# Case 2: All completed → exit 0
test_cwd="$tmpdir/case2"
mkdir -p "$test_cwd"
cat > "$test_cwd/checkpoint.yaml" << 'YAML'
meta:
  planning_done: true
tasks:
  - id: t1
    title: Done task
    status: completed
YAML
run_test "Case 2: All completed → allow stop" 0 "" "{\"cwd\":\"$test_cwd\"}" "$test_cwd"

# Case 3: Pending tasks → block with JSON
test_cwd="$tmpdir/case3"
mkdir -p "$test_cwd"
cat > "$test_cwd/checkpoint.yaml" << 'YAML'
meta:
  planning_done: true
tasks:
  - id: t1
    title: Done task
    status: completed
  - id: t2
    title: Pending task
    status: pending
    depends_on:
      - t1
YAML
run_test "Case 3: Pending tasks → block" 0 '"decision":"block"' "{\"cwd\":\"$test_cwd\"}" "$test_cwd"

# Case 4: stop_hook_active=true → exit 0 (infinite loop prevention)
test_cwd="$tmpdir/case4"
mkdir -p "$test_cwd"
cat > "$test_cwd/checkpoint.yaml" << 'YAML'
meta:
  planning_done: true
tasks:
  - id: t1
    title: Pending task
    status: pending
YAML
run_test "Case 4: stop_hook_active → allow stop" 0 "" "{\"cwd\":\"$test_cwd\",\"stop_hook_active\":\"true\"}" "$test_cwd"

echo ""
echo "=== Results: $PASS/$TOTAL passed ==="
if [[ $FAIL -gt 0 ]]; then
    echo "FAILED: $FAIL tests"
    exit 1
fi
echo "All tests passed!"
