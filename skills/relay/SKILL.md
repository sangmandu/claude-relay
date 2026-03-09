---
name: relay
description: Run the full autonomous relay pipeline — plan tasks collaboratively then execute them all with parallel support
---

You are running the full claude-relay pipeline. Follow these phases in order.

## Phase 0: Session Initialization

Before anything else, determine which checkpoint file to use.

1. **Scan** for all `checkpoint-*.yaml` files in the current working directory
2. **If none exist**: Ask the user what they want to accomplish, then generate a filename: `checkpoint-{short-description}.yaml` (e.g., `checkpoint-onboarding-refactor.yaml`). Proceed to Phase 1.
3. **If one or more exist**: List them with status summary (total/completed/pending tasks, project_name from meta). Then ask:
   - "Resume one of these?" → user picks one → proceed to Phase 1 or Phase 2 depending on `planning_done`
   - "Start a new task?" → generate a new filename and proceed to Phase 1

**Filename rules**:
- Format: `checkpoint-{kebab-case-description}.yaml`
- Keep it short but descriptive (3-5 words max)
- Never use plain `checkpoint.yaml` — always include a description

Store the chosen filename as `CHECKPOINT_FILE` for all subsequent phases.

## Phase 1: Planning

**If checkpoint file exists** and `meta.planning_done` is `true`:
- Show the user a summary of the existing plan (task count, completed count, pending count)
- Ask: "Resume execution, or re-plan?"
- If resume → skip to Phase 2
- If re-plan → delete the file and proceed with planning below

**If checkpoint file does NOT exist** (or user chose re-plan):
- Follow the `/relay-plan` skill behavior:
  1. Ask the user what they want to accomplish (skip if already answered in Phase 0)
  2. Explore relevant files and context
  3. Break it down into tasks with `depends_on` for parallelism
  4. Iterate with the user until they approve
  5. Write the checkpoint file with `planning_done: true`

## Phase 2: Execution

Once the checkpoint file is ready with `planning_done: true`, begin the autonomous execution loop.

### Execution Loop

Repeat until all tasks are completed:

1. **Read the checkpoint file** to get current state
2. **Find ready tasks**: tasks with status `pending` whose `depends_on` are all `completed`
3. **If no ready tasks and pending tasks exist**: something is blocked — report to user and stop
4. **If 1 ready task**: Execute it directly in the current session
   - Read the task title and do exactly what it says
   - When done, update the task's status to `completed` in the checkpoint file (set `completed_at` to current ISO timestamp)
5. **If multiple ready tasks**: Use the Agent tool to run them in parallel
   - Launch one agent per task (up to 4 concurrent)
   - Each agent prompt: "Read {CHECKPOINT_FILE}. Execute ONLY task '[task_id]': [task_title]. When done, update ONLY that task's status to 'completed' in {CHECKPOINT_FILE} with completed_at timestamp. Do NOT touch other tasks."
   - Wait for all agents to complete
   - Re-read the checkpoint file to verify completions
6. **After each batch**: Briefly note key findings relevant to upcoming tasks
7. **Loop back to step 1**

### Execution Rules

- Always re-read the checkpoint file before each iteration (other agents may have modified it)
- Only update the status of the task you are working on
- If a task fails, set its status to `failed` and continue with other tasks
- Keep task execution focused — do exactly what the title says, no more
- After ALL tasks complete, tell the user "All tasks completed!" and offer to answer follow-up questions

## Stop Hook (Auto-Continue)

This plugin includes a **Stop Hook** — when pending tasks remain in checkpoint files, Claude is automatically prevented from stopping. You don't need to remind Claude to keep going; the hook handles it.

- If all tasks are completed, Claude stops normally
- If pending tasks remain, the hook blocks the stop and shows the next task
- The `stop_hook_active` flag provides an escape hatch to force stop if needed

## Important

- Use `scripts/checkpoint.py` (at `${CLAUDE_PLUGIN_ROOT}/scripts/checkpoint.py`) if available for safe concurrent checkpoint updates with file locking. Pass `-f {CHECKPOINT_FILE}` to specify the file.
- The Agent tool provides parallelism within a single Claude Code session — no external shell script needed
- Be autonomous during Phase 2 — don't ask the user for confirmation between tasks
- The Stop Hook ensures Claude keeps running until all tasks are done — no shell wrapper needed
