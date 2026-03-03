#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"
SKILL_PATH="$SCRIPT_DIR/skills/plan-checkpoint.md"
TEMPLATE_PATH="$SCRIPT_DIR/templates/checkpoint.template.yaml"

WORK_DIR="${1:-.}"
CHECKPOINT_FILE="$WORK_DIR/checkpoint.yaml"
LOG_FILE="$WORK_DIR/relay_log.txt"
SESSION_FILE="$WORK_DIR/.relay_session"
MAX_ITER="${RELAY_MAX_ITER:-50}"
MAX_STALE="${RELAY_MAX_STALE:-5}"

unset CLAUDECODE

echo "=== claude-relay ==="
echo "Work dir: $WORK_DIR"
echo "Max iterations: $MAX_ITER"
echo "Max stale rounds: $MAX_STALE"
echo ""

get_checkpoint_hash() {
  if [ -f "$CHECKPOINT_FILE" ]; then
    md5 -q "$CHECKPOINT_FILE" 2>/dev/null || md5sum "$CHECKPOINT_FILE" | awk '{print $1}'
  else
    echo "none"
  fi
}

has_pending_tasks() {
  if [ -f "$CHECKPOINT_FILE" ]; then
    grep -q "status: pending\|status: in_progress" "$CHECKPOINT_FILE"
    return $?
  fi
  return 1
}

is_planning_done() {
  if [ -f "$CHECKPOINT_FILE" ]; then
    grep -q "planning_done: true" "$CHECKPOINT_FILE"
    return $?
  fi
  return 1
}

save_session() {
  local phase="$1"
  local sid="$2"
  echo "${phase}:${sid}" > "$SESSION_FILE"
}

load_session() {
  local phase="$1"
  if [ -f "$SESSION_FILE" ]; then
    local saved
    saved=$(cat "$SESSION_FILE")
    local saved_phase="${saved%%:*}"
    local saved_sid="${saved#*:}"
    if [ "$saved_phase" = "$phase" ] && [ -n "$saved_sid" ]; then
      echo "$saved_sid"
      return 0
    fi
  fi
  return 1
}

run_claude_streaming() {
  local output_file
  output_file=$(mktemp)

  "$@" --output-format stream-json 2>&1 | while IFS= read -r line; do
    echo "$line" >> "$output_file"

    local msg_type
    msg_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null) || continue

    case "$msg_type" in
      assistant)
        local text
        text=$(echo "$line" | jq -r '.message.content[]? | select(.type=="text") | .text // empty' 2>/dev/null) || true
        if [ -n "$text" ]; then
          echo "$text"
        fi
        ;;
      result)
        local result_text
        result_text=$(echo "$line" | jq -r '.result // empty' 2>/dev/null) || true
        if [ -n "$result_text" ]; then
          echo "$result_text"
        fi
        local cost
        cost=$(echo "$line" | jq -r '.cost_usd // empty' 2>/dev/null) || true
        if [ -n "$cost" ]; then
          echo -e "\033[90m[cost: \$${cost}]\033[0m"
        fi
        ;;
    esac
  done

  if [ -f "$LOG_FILE" ] && [ -f "$output_file" ]; then
    cat "$output_file" >> "$LOG_FILE"
  fi
  rm -f "$output_file"
}

# ============================================================
# Phase 1: Interactive planning with user
# ============================================================
phase1_planning() {
  echo "━━━ Phase 1: Planning (interactive) ━━━"
  echo "Starting interactive session to build checkpoint pipeline..."
  echo ""

  local SESSION_ID
  if SESSION_ID=$(load_session "phase1"); then
    echo "Resuming previous Phase 1 session: $SESSION_ID"
  else
    SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    save_session "phase1" "$SESSION_ID"
    echo "New session: $SESSION_ID"
  fi

  PHASE1_PROMPT="Read the skill file at $SKILL_PATH and follow its instructions. Working directory: $WORK_DIR. Help the user create a checkpoint.yaml for their task. If checkpoint.yaml already exists, review it with the user. Template reference: $TEMPLATE_PATH"

  echo ""
  echo -e "\033[36m━━━ Claude ━━━\033[0m"
  run_claude_streaming claude --session-id "$SESSION_ID" \
    --dangerously-skip-permissions \
    -p "$PHASE1_PROMPT" \
    "$WORK_DIR"

  while ! is_planning_done; do
    echo ""
    echo "┌─────────────────────────────────────────┐"
    echo "│  Enter your feedback (or 'done' to skip) │"
    echo "└─────────────────────────────────────────┘"
    read -r -p "You > " user_input

    if [ -z "$user_input" ]; then
      continue
    fi

    echo ""
    echo -e "\033[90m━━━ You: $user_input ━━━\033[0m"
    echo ""
    echo -e "\033[36m━━━ Claude ━━━\033[0m"

    run_claude_streaming claude --resume "$SESSION_ID" \
      --dangerously-skip-permissions \
      -p "$user_input" \
      "$WORK_DIR"
  done

  echo ""
  echo "[relay] Phase 1 complete. Checkpoint pipeline is ready."
  echo ""
}

# ============================================================
# Phase 2: Autonomous execution loop
# ============================================================
phase2_execution() {
  echo "━━━ Phase 2: Autonomous Execution ━━━"

  local SESSION_ID
  if SESSION_ID=$(load_session "phase2"); then
    echo "Resuming previous Phase 2 session: $SESSION_ID"
  else
    SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    save_session "phase2" "$SESSION_ID"
    echo "New session: $SESSION_ID"
  fi

  echo "Log file: $LOG_FILE"
  echo ""

  read -r -d '' SYSTEM_PROMPT << 'SYSPROMPT' || true
You are running in an autonomous relay loop.
The user has fully delegated this work to you. Each message you receive is a system-level
trigger from the relay runner, not a human typing in real-time.

## Your protocol

1. Read checkpoint.yaml in the working directory
2. Find the first task with status "pending" or "in_progress"
3. If "pending": set status to "in_progress" and started_at to current time, save checkpoint.yaml
4. Execute the task thoroughly
5. When done: set status to "completed" and completed_at to current time, update notes if needed, save checkpoint.yaml
6. Do NOT proceed to the next task in the same turn. One task per turn.

## Important
- Always read checkpoint.yaml at the start of each turn to get current state
- Always save checkpoint.yaml after any status change
- If a task is blocked or unclear, write the reason in the task notes field and move on to the next task
- Keep your work focused on exactly what the task title and notes describe
SYSPROMPT

  RELAY_PROMPT="(This is a recurring system message from the relay runner.) Read checkpoint.yaml and execute the next pending task according to your protocol. Current working directory: $WORK_DIR"

  stale_count=0
  prev_hash=$(get_checkpoint_hash)

  for i in $(seq 1 "$MAX_ITER"); do
    echo ""
    echo -e "\033[33m--- Iteration $i / $MAX_ITER ---\033[0m"

    if ! has_pending_tasks; then
      echo "[relay] All tasks completed!"
      break
    fi

    local current_task
    current_task=$(grep -A1 "status: pending\|status: in_progress" "$CHECKPOINT_FILE" | head -1 | sed 's/.*title: "\(.*\)"/\1/' 2>/dev/null || echo "unknown")
    echo -e "\033[36m  Task: $current_task\033[0m"
    echo ""

    if [ "$i" -eq 1 ] && ! load_session "phase2" >/dev/null 2>&1; then
      run_claude_streaming claude --session-id "$SESSION_ID" \
        --system-prompt "$SYSTEM_PROMPT" \
        --dangerously-skip-permissions \
        -p "$RELAY_PROMPT" \
        "$WORK_DIR"
    else
      run_claude_streaming claude --resume "$SESSION_ID" \
        --dangerously-skip-permissions \
        -p "$RELAY_PROMPT" \
        "$WORK_DIR"
    fi

    curr_hash=$(get_checkpoint_hash)
    if [ "$curr_hash" = "$prev_hash" ]; then
      stale_count=$((stale_count + 1))
      echo -e "\033[31m[relay] No checkpoint change detected ($stale_count / $MAX_STALE)\033[0m"

      if [ "$stale_count" -ge "$MAX_STALE" ]; then
        echo "[relay] Stale limit reached. Stopping."
        break
      fi
    else
      stale_count=0
      prev_hash="$curr_hash"
    fi

    sleep 2
  done

  echo ""
  echo "━━━ Relay Complete ━━━"
  echo "Checkpoint: $CHECKPOINT_FILE"
  echo "Log: $LOG_FILE"

  if has_pending_tasks; then
    echo "Status: INCOMPLETE (some tasks remain)"
    exit 1
  else
    echo "Status: ALL DONE"
    rm -f "$SESSION_FILE"
  fi
}

# ============================================================
# Main
# ============================================================

if is_planning_done; then
  echo "[relay] checkpoint.yaml already finalized. Skipping Phase 1."
  phase2_execution
else
  phase1_planning
  phase2_execution
fi
