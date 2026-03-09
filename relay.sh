#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR"
CHECKPOINT_PY="$SCRIPT_DIR/scripts/checkpoint.py"
ORCHESTRATOR_AGENT="$SCRIPT_DIR/agents/relay-orchestrator.md"

WORK_DIR="${1:-.}"
CHECKPOINT_NAME="${2:-}"

if [ -z "$CHECKPOINT_NAME" ]; then
  existing=($(ls "$WORK_DIR"/checkpoint-*.yaml 2>/dev/null))
  if [ ${#existing[@]} -eq 1 ]; then
    CHECKPOINT_FILE="${existing[0]}"
    echo "Using existing checkpoint: $(basename "$CHECKPOINT_FILE")"
  elif [ ${#existing[@]} -gt 1 ]; then
    echo "Multiple checkpoint files found:"
    for i in "${!existing[@]}"; do
      echo "  [$((i+1))] $(basename "${existing[$i]}")"
    done
    read -r -p "Select (number) or enter a new name: " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#existing[@]} ]; then
      CHECKPOINT_FILE="${existing[$((selection-1))]}"
    else
      CHECKPOINT_FILE="$WORK_DIR/checkpoint-${selection}.yaml"
    fi
  else
    read -r -p "Describe this task (short, kebab-case): " task_name
    CHECKPOINT_FILE="$WORK_DIR/checkpoint-${task_name}.yaml"
  fi
else
  CHECKPOINT_FILE="$WORK_DIR/checkpoint-${CHECKPOINT_NAME}.yaml"
fi
LOG_DIR="$WORK_DIR/logs"
LOG_FILE="$WORK_DIR/relay_log.txt"
SESSION_FILE="$WORK_DIR/.relay_session"
MAX_ITER="${RELAY_MAX_ITER:-50}"
MAX_STALE="${RELAY_MAX_STALE:-5}"
MAX_PARALLEL="${RELAY_MAX_PARALLEL:-4}"

unset CLAUDECODE

mkdir -p "$LOG_DIR"

echo "=== claude-relay ==="
echo "Work dir: $WORK_DIR"
echo "Max iterations: $MAX_ITER"
echo "Max stale rounds: $MAX_STALE"
echo "Max parallel: $MAX_PARALLEL"
echo ""

# ============================================================
# Checkpoint helpers (delegating to scripts/checkpoint.py)
# ============================================================

ckpt() {
  python3 "$CHECKPOINT_PY" -f "$CHECKPOINT_FILE" "$@"
}

get_checkpoint_hash() {
  if [ -f "$CHECKPOINT_FILE" ]; then
    md5 -q "$CHECKPOINT_FILE" 2>/dev/null || md5sum "$CHECKPOINT_FILE" | awk '{print $1}'
  else
    echo "none"
  fi
}

has_pending_tasks() {
  ckpt has_pending
}

is_planning_done() {
  ckpt is_planning_done
}

get_ready_tasks() {
  ckpt get_ready_tasks
}

get_task_field() {
  ckpt get_task_field "$1" "$2"
}

update_task_status() {
  ckpt update_task_status "$1" "$2"
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
# Phase 1: Interactive planning with plugin
# ============================================================
phase1_planning() {
  echo "━━━ Phase 1: Planning (interactive) ━━━"
  echo "Use /relay-plan to build your checkpoint pipeline."
  echo ""

  local SESSION_ID
  if SESSION_ID=$(load_session "phase1"); then
    echo "Resuming previous Phase 1 session: $SESSION_ID"
  else
    SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    save_session "phase1" "$SESSION_ID"
    echo "New session: $SESSION_ID"
  fi

  local PHASE1_PROMPT="You have the relay plugin loaded. The user can use /relay-plan to build a checkpoint pipeline. Working directory: $WORK_DIR. If checkpoint.yaml already exists, review it with the user."

  echo ""
  echo -e "\033[36m━━━ Claude ━━━\033[0m"
  run_claude_streaming claude --session-id "$SESSION_ID" \
    --plugin-dir "$PLUGIN_DIR" \
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
# Run a single task via worker with plugin
# ============================================================
run_single_task() {
  local task_id="$1"
  local task_title
  task_title="$(get_task_field "$task_id" "title")"
  local timestamp
  timestamp="$(date '+%Y%m%d_%H%M%S')"
  local task_log="$LOG_DIR/${task_id}_${timestamp}.log"

  echo -e "\033[36m  ▶ [$task_id] $task_title\033[0m"

  update_task_status "$task_id" "in_progress"

  local TASK_PROMPT="(This is an autonomous relay task.)
Read checkpoint.yaml in $WORK_DIR. Execute ONLY task '$task_id': $task_title
Follow these rules:
1. Read checkpoint.yaml to understand context and your specific task
2. Execute the task thoroughly
3. When done, update ONLY your task '$task_id' status to 'completed' in checkpoint.yaml
4. Do NOT touch other tasks' statuses
5. Keep work focused on exactly what the task describes"

  local exit_code=0
  claude --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    -p "$TASK_PROMPT" \
    "$WORK_DIR" > "$task_log" 2>&1 || exit_code=$?

  if [ $exit_code -ne 0 ]; then
    echo -e "\033[31m  ✗ [$task_id] Failed (exit code $exit_code)\033[0m"
    update_task_status "$task_id" "failed"
    return 1
  fi

  local current_status
  current_status="$(get_task_field "$task_id" "status")"
  if [ "$current_status" = "completed" ]; then
    echo -e "\033[32m  ✓ [$task_id] Completed\033[0m"
  else
    echo -e "\033[32m  ✓ [$task_id] Done (marking completed)\033[0m"
    update_task_status "$task_id" "completed"
  fi
  return 0
}

# ============================================================
# Collect task results from logs for session context
# ============================================================
collect_batch_summary() {
  local task_ids="$1"
  local summary="The following tasks just completed:\n"
  for tid in $task_ids; do
    local title notes
    title="$(get_task_field "$tid" "title")"
    notes="$(get_task_field "$tid" "notes")"
    summary="$summary\n- [$tid] $title"
    if [ -n "$notes" ] && [ "$notes" != "None" ] && [ "$notes" != "" ]; then
      summary="$summary — notes: $notes"
    fi
  done
  echo -e "$summary"
}

# ============================================================
# Load orchestrator system prompt from agent definition
# ============================================================
load_system_prompt() {
  python3 -c "
import sys, yaml

content = open('$ORCHESTRATOR_AGENT').read()
if content.startswith('---'):
    parts = content.split('---', 2)
    if len(parts) >= 3:
        try:
            yaml.safe_load(parts[1])
            print(parts[2].strip())
        except yaml.YAMLError:
            print(content)
    else:
        print(content)
else:
    print(content)
"
}

# ============================================================
# Phase 2: Autonomous execution loop (with parallel support)
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

  echo "Log dir: $LOG_DIR/"
  echo ""

  local SYSTEM_PROMPT
  SYSTEM_PROMPT="$(load_system_prompt)"

  local first_run=true
  stale_count=0
  prev_hash=$(get_checkpoint_hash)

  for i in $(seq 1 "$MAX_ITER"); do
    echo ""
    echo -e "\033[33m--- Iteration $i / $MAX_ITER ---\033[0m"

    if ! has_pending_tasks; then
      echo "[relay] All tasks completed!"
      break
    fi

    local ready_json
    ready_json="$(get_ready_tasks)"
    local ready_count
    ready_count="$(echo "$ready_json" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')"

    if [ "$ready_count" -eq 0 ]; then
      if has_pending_tasks; then
        echo -e "\033[31m[relay] Tasks pending but none ready (blocked by dependencies or in_progress)\033[0m"
        stale_count=$((stale_count + 1))
        if [ "$stale_count" -ge "$MAX_STALE" ]; then
          echo "[relay] Stale limit reached. Stopping."
          break
        fi
        sleep 3
        continue
      else
        echo "[relay] All tasks completed!"
        break
      fi
    fi

    local task_ids
    task_ids="$(echo "$ready_json" | python3 -c "
import sys, json
ids = json.load(sys.stdin)[:$MAX_PARALLEL]
print(' '.join(ids))
")"
    local launch_count
    launch_count=$(echo $task_ids | wc -w | tr -d ' ')

    if [ "$launch_count" -eq 1 ]; then
      local tid="$task_ids"
      local title
      title="$(get_task_field "$tid" "title")"
      echo -e "\033[36m  ▶ [$tid] $title (main session)\033[0m"

      update_task_status "$tid" "in_progress"

      local TASK_PROMPT="(Relay iteration $i) Read checkpoint.yaml and execute task '$tid': $title. When done, set its status to 'completed' in checkpoint.yaml. Working directory: $WORK_DIR"

      if [ "$first_run" = true ]; then
        run_claude_streaming claude --session-id "$SESSION_ID" \
          --system-prompt "$SYSTEM_PROMPT" \
          --plugin-dir "$PLUGIN_DIR" \
          --dangerously-skip-permissions \
          -p "$TASK_PROMPT" \
          "$WORK_DIR"
        first_run=false
      else
        run_claude_streaming claude --resume "$SESSION_ID" \
          --dangerously-skip-permissions \
          -p "$TASK_PROMPT" \
          "$WORK_DIR"
      fi

      local current_status
      current_status="$(get_task_field "$tid" "status")"
      if [ "$current_status" = "completed" ]; then
        echo -e "\033[32m  ✓ [$tid] Completed\033[0m"
      else
        echo -e "\033[32m  ✓ [$tid] Done (marking completed)\033[0m"
        update_task_status "$tid" "completed"
      fi

    else
      echo -e "\033[35m  Parallel batch: $ready_count ready, launching $launch_count tasks\033[0m"

      local pids=()
      local pid_task_map=""

      for tid in $task_ids; do
        run_single_task "$tid" &
        local pid=$!
        pids+=("$pid")
        pid_task_map="$pid_task_map $pid:$tid"
      done

      for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
          local failed_tid
          failed_tid="$(echo "$pid_task_map" | tr ' ' '\n' | grep "^$pid:" | cut -d: -f2)"
          echo -e "\033[31m  ✗ Task $failed_tid worker failed\033[0m"
        fi
      done

      local batch_summary
      batch_summary="$(collect_batch_summary "$task_ids")"

      local SYNC_PROMPT="(Relay iteration $i — batch sync) $batch_summary

Re-read checkpoint.yaml to see current state. Briefly note any key findings from the completed tasks that might be relevant for upcoming work."

      echo -e "\033[90m  Syncing batch results to main session...\033[0m"

      if [ "$first_run" = true ]; then
        run_claude_streaming claude --session-id "$SESSION_ID" \
          --system-prompt "$SYSTEM_PROMPT" \
          --plugin-dir "$PLUGIN_DIR" \
          --dangerously-skip-permissions \
          -p "$SYNC_PROMPT" \
          "$WORK_DIR"
        first_run=false
      else
        run_claude_streaming claude --resume "$SESSION_ID" \
          --dangerously-skip-permissions \
          -p "$SYNC_PROMPT" \
          "$WORK_DIR"
      fi
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
  echo "Logs: $LOG_DIR/"
  echo ""
  echo "Session ID: $SESSION_ID"
  echo "  → To continue: claude --resume $SESSION_ID"

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
