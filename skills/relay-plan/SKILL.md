---
name: relay-plan
description: Collaboratively build a checkpoint.yaml pipeline for autonomous task execution with parallel task support
---

<plan-checkpoint>

You are helping the user create a checkpoint pipeline for an autonomous task.

## Your Role

The user has a task they want to fully delegate to Claude Code running in a loop.
Your job is to **collaboratively build a checkpoint.yaml** that defines every step needed.

## Process

1. **Understand the problem**: Ask the user what they want to accomplish. Explore the relevant files, folders, and context.
2. **Break it down**: Propose a phased task list (investigation → analysis → implementation → verification).
3. **Identify parallelism**: Tasks with no dependencies on each other should have the same (or no) `depends_on` — the runner will execute them concurrently.
4. **Refine together**: The user may add, remove, or reorder tasks. Iterate until they're satisfied.
5. **Write checkpoint.yaml**: When the user confirms, generate the final checkpoint.yaml in the working directory.

## checkpoint.yaml Format

```yaml
meta:
  project_name: "descriptive-name"
  created_at: "ISO-8601"
  planning_done: false
  phase: "planning"
  stale_count: 0
  max_stale: 5

tasks:
  - id: short_snake_case_id
    title: "Human readable title"
    status: pending
    depends_on: []           # task ids that must complete first
    started_at: null
    completed_at: null
    notes: ""
```

## Rules

- Each task should be **one clear unit of work** that Claude can complete in a single session turn
- Use `depends_on` to express task dependencies — tasks without dependencies (or whose dependencies are all completed) will run **in parallel**
- Tasks that can run independently SHOULD have empty or identical `depends_on` to maximize parallelism
- Include investigation/analysis tasks before implementation tasks
- Task titles should be specific enough that a fresh Claude session can understand what to do just by reading it
- **Every implementation task must be followed by a verification task** that tests or validates the implementation actually works (run it, execute tests, check output, etc.)
- **The final task must always be writing a report** (REPORT.md) that summarizes: what was done, what was found, key results, and any remaining issues
- When the user approves the final list, set `meta.planning_done: true` and `meta.phase: "executing"`

## Parallelism Tips

When breaking down tasks, actively look for opportunities to parallelize:
- Multiple independent analyses → parallel
- Multiple independent implementations → parallel
- Anything that reads from the same source but produces different outputs → parallel
- Only add `depends_on` when a task truly needs another task's output

## Completion Signal

When checkpoint.yaml is written with `planning_done: true`, tell the user:
"Checkpoint pipeline is ready. Run phase 2 to begin autonomous execution."

</plan-checkpoint>
