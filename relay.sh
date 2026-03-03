#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"
SKILL_PATH="$SCRIPT_DIR/skills/plan-checkpoint.md"
TEMPLATE_PATH="$SCRIPT_DIR/templates/checkpoint.template.yaml"

WORK_DIR="${1:-.}"
CHECKPOINT_FILE="$WORK_DIR/checkpoint.yaml"
LOG_FILE="$WORK_DIR/relay_log.txt"
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

# ============================================================
# Phase 1: Interactive planning with user
# ============================================================
phase1_planning() {
  echo "━━━ Phase 1: Planning (interactive) ━━━"
  echo "Starting interactive session to build checkpoint pipeline..."
  echo ""

  SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
  echo "Session ID: $SESSION_ID"

  PHASE1_PROMPT="Read the skill file at $SKILL_PATH and follow its instructions. Working directory: $WORK_DIR. Help the user create a checkpoint.yaml for their task. If checkpoint.yaml already exists, review it with the user. Template reference: $TEMPLATE_PATH"

  claude --session-id "$SESSION_ID" \
    --permission-mode default \
    -p "$PHASE1_PROMPT" \
    "$WORK_DIR"

  while ! is_planning_done; do
    echo ""
    echo "[relay] checkpoint.yaml not finalized yet. Continuing session..."
    echo "  (Type your feedback. Claude will resume the same session.)"
    echo ""

    read -r -p "> " user_input

    if [ -z "$user_input" ]; then
      continue
    fi

    claude --resume "$SESSION_ID" \
      --permission-mode default \
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

  SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
  echo "Session ID: $SESSION_ID"
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
    echo "--- Iteration $i / $MAX_ITER ---"

    if ! has_pending_tasks; then
      echo "[relay] All tasks completed!"
      break
    fi

    if [ "$i" -eq 1 ]; then
      claude --session-id "$SESSION_ID" \
        --system-prompt "$SYSTEM_PROMPT" \
        --dangerously-skip-permissions \
        -p "$RELAY_PROMPT" \
        "$WORK_DIR" 2>&1 | tee -a "$LOG_FILE"
    else
      claude --resume "$SESSION_ID" \
        --dangerously-skip-permissions \
        -p "$RELAY_PROMPT" \
        "$WORK_DIR" 2>&1 | tee -a "$LOG_FILE"
    fi

    curr_hash=$(get_checkpoint_hash)
    if [ "$curr_hash" = "$prev_hash" ]; then
      stale_count=$((stale_count + 1))
      echo "[relay] No checkpoint change detected ($stale_count / $MAX_STALE)"

      if [ "$stale_count" -ge "$MAX_STALE" ]; then
        echo "[relay] Stale limit reached. Stopping."
        break
      fi
    else
      stale_count=0
      prev_hash="$curr_hash"
    fi

    echo ""
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
