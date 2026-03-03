---
name: relay-run
description: Execute Phase 2 only — run all pending tasks from an existing checkpoint.yaml with parallel support
---

You are running Phase 2 (execution only) of the claude-relay pipeline.

## Pre-check

Read `checkpoint.yaml` in the current working directory.

- If it does NOT exist: Tell the user "No checkpoint.yaml found. Use `/relay-plan` first to create a task pipeline, or `/relay` for the full flow."
- If `meta.planning_done` is NOT `true`: Tell the user "Planning is not finalized. Use `/relay-plan` to finish planning first."
- Otherwise: proceed to execution.

Show the user a quick summary:
- Total tasks, completed, pending, in_progress, failed
- Then say "Starting execution..." and begin.

## Execution Loop

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

## Execution Rules

- Always re-read checkpoint.yaml before each iteration (other agents may have modified it)
- Only update the status of the task you are working on
- If a task fails, set its status to `failed` and continue with other tasks
- Keep task execution focused — do exactly what the title says, no more
- After ALL tasks complete, tell the user "All tasks completed!" and offer to answer follow-up questions
- Be autonomous — don't ask the user for confirmation between tasks
- The **Stop Hook** automatically prevents Claude from stopping while tasks remain — no manual looping needed
- Multiple checkpoint files are supported (checkpoint.yaml, checkpoint_2.yaml, etc.)
