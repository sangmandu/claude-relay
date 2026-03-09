---
name: relay-run
description: Execute Phase 2 only — run all pending tasks from an existing checkpoint file with parallel support
---

You are running Phase 2 (execution only) of the claude-relay pipeline.

## Pre-check: Select Checkpoint File

1. **Scan** for all `checkpoint-*.yaml` files in the current working directory
2. **If none exist**: Tell the user "No checkpoint files found. Use `/relay-plan` first to create a task pipeline, or `/relay` for the full flow."
3. **If one exists**: Use it automatically
4. **If multiple exist**: List them with status summary (total/completed/pending, project_name). Ask the user which one to execute.

Once a file is selected:
- If `meta.planning_done` is NOT `true`: Tell the user "Planning is not finalized. Use `/relay-plan` to finish planning first."
- Otherwise: proceed to execution.

Show the user a quick summary:
- Checkpoint file name
- Total tasks, completed, pending, in_progress, failed
- Then say "Starting execution..." and begin.

## Execution Loop

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

## Execution Rules

- Always re-read the checkpoint file before each iteration (other agents may have modified it)
- Only update the status of the task you are working on
- If a task fails, set its status to `failed` and continue with other tasks
- Keep task execution focused — do exactly what the title says, no more
- After ALL tasks complete, tell the user "All tasks completed!" and offer to answer follow-up questions
- Be autonomous — don't ask the user for confirmation between tasks
- The **Stop Hook** automatically prevents Claude from stopping while tasks remain — no manual looping needed
