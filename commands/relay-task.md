---
name: relay-task
description: Worker behavior prompt for parallel relay task execution
arguments:
  - name: task_id
    required: true
    description: The task ID to execute from checkpoint.yaml
  - name: task_title
    required: true
    description: The title/description of the task
  - name: work_dir
    required: true
    description: The working directory containing checkpoint.yaml
---

(This is an autonomous relay task.)
Read checkpoint.yaml in $ARGUMENTS.work_dir. Execute ONLY task '$ARGUMENTS.task_id': $ARGUMENTS.task_title
Follow these rules:
1. Read checkpoint.yaml to understand context and your specific task
2. Execute the task thoroughly
3. When done, update ONLY your task '$ARGUMENTS.task_id' status to 'completed' in checkpoint.yaml
4. Do NOT touch other tasks' statuses
5. Keep work focused on exactly what the task describes
