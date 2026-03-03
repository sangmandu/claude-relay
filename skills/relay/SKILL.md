---
name: relay
description: Run the full autonomous relay pipeline — plan tasks collaboratively then execute them all with parallel support
---

You are running the full claude-relay pipeline. Follow these phases in order.

## Phase 1: Planning

Check if `checkpoint.yaml` exists in the current working directory.

**If it exists** and `meta.planning_done` is `true`:
- Show the user a summary of the existing plan (task count, completed count, pending count)
- Ask: "Existing plan found. Resume execution, or start fresh?"
- If resume → skip to Phase 2
- If start fresh → delete checkpoint.yaml and proceed with planning below

**If it does NOT exist** (or user chose start fresh):
- Follow the `/relay-plan` skill behavior:
  1. Ask the user what they want to accomplish
  2. Explore relevant files and context
  3. Break it down into tasks with `depends_on` for parallelism
  4. Iterate with the user until they approve
  5. Write checkpoint.yaml with `planning_done: true`

## Phase 2: Execution

Once checkpoint.yaml is ready with `planning_done: true`, begin the autonomous execution loop.

### Execution Loop

Repeat until all tasks are completed:

1. **Read checkpoint.yaml** to get current state
2. **Find ready tasks**: tasks with status `pending` whose `depends_on` are all `completed`
3. **If no ready tasks and pending tasks exist**: something is blocked — report to user and stop
4. **If 1 ready task**: Execute it directly in the current session
   - Read the task title and do exactly what it says
   - When done, update the task's status to `completed` in checkpoint.yaml (set `completed_at` to current ISO timestamp)
5. **If multiple ready tasks**: Use the Agent tool to run them in parallel
   - Launch one agent per task (up to 4 concurrent)
   - Each agent prompt: "Read checkpoint.yaml. Execute ONLY task '[task_id]': [task_title]. When done, update ONLY that task's status to 'completed' in checkpoint.yaml with completed_at timestamp. Do NOT touch other tasks."
   - Wait for all agents to complete
   - Re-read checkpoint.yaml to verify completions
6. **After each batch**: Briefly note key findings relevant to upcoming tasks
7. **Loop back to step 1**

### Execution Rules

- Always re-read checkpoint.yaml before each iteration (other agents may have modified it)
- Only update the status of the task you are working on
- If a task fails, set its status to `failed` and continue with other tasks
- Keep task execution focused — do exactly what the title says, no more
- After ALL tasks complete, tell the user "All tasks completed!" and offer to answer follow-up questions

## Important

- Use `scripts/checkpoint.py` (at `${CLAUDE_PLUGIN_ROOT}/scripts/checkpoint.py`) if available for safe concurrent checkpoint updates with file locking
- The Agent tool provides parallelism within a single Claude Code session — no external shell script needed
- Be autonomous during Phase 2 — don't ask the user for confirmation between tasks
