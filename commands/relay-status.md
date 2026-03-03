---
name: relay-status
description: Display a formatted summary of all tasks and their statuses from checkpoint.yaml
---

Read the `checkpoint.yaml` file in the current working directory and display a formatted summary.

## Format

1. Show project metadata: project name, phase, planning status
2. Show a task summary table with columns: Status Icon | Task ID | Title | Status
   - Use these status icons:
     - completed: ✅
     - in_progress: 🔄
     - pending: ⏳
     - failed: ❌
3. Show a summary line with counts: e.g. "3/10 completed, 2 in progress, 5 pending"
4. If there are dependency chains, note which pending tasks are ready (all dependencies completed)

## Rules
- Read checkpoint.yaml using the Read tool
- Do NOT modify checkpoint.yaml — this is a read-only status command
- If checkpoint.yaml does not exist, inform the user
- Keep output concise and scannable
