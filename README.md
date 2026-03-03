# claude-relay

Checkpoint-driven autonomous task runner for Claude Code.

Define a checklist, let Claude work through it one by one, unattended.

## How it works

```
Phase 1 (Interactive)          Phase 2 (Autonomous)
┌─────────────────────┐       ┌─────────────────────────────┐
│ User ↔ Claude        │       │ Loop:                       │
│ Build checkpoint.yaml│──────▶│  1. Read checkpoint.yaml    │
│ together             │       │  2. Find next [ ] task      │
└─────────────────────┘       │  3. Execute it              │
                               │  4. Mark [x], save yaml     │
                               │  5. Repeat until all [x]    │
                               └─────────────────────────────┘
```

- **Phase 1**: You and Claude collaboratively build a task checklist (`checkpoint.yaml`)
- **Phase 2**: Claude autonomously works through each task, one per turn, updating the yaml after each completion

Context is maintained via `--resume` (same session), and `checkpoint.yaml` tracks progress as a file so you always know where things stand.

## Quick Start

```bash
# Run in any project directory
./relay.sh /path/to/your/project

# Phase 1: interactive planning starts
# Phase 2: autonomous execution follows automatically
```

If you already have a `checkpoint.yaml` with `planning_done: true`, Phase 1 is skipped.

## Installation

### Option 1: Symlink to PATH (run from anywhere)

```bash
ln -s $(pwd)/relay.sh /usr/local/bin/claude-relay

# Then use from any directory:
claude-relay .
claude-relay ~/projects/my-app
```

### Option 2: Global Claude Code skill

Copy the planning skill so it's available in all Claude Code sessions:

```bash
mkdir -p ~/.claude/skills
cp skills/plan-checkpoint.md ~/.claude/skills/
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `RELAY_MAX_ITER` | 50 | Maximum loop iterations |
| `RELAY_MAX_STALE` | 5 | Stop after N iterations with no checkpoint change |

```bash
RELAY_MAX_ITER=100 RELAY_MAX_STALE=3 claude-relay ./my-project
```

## checkpoint.yaml Format

```yaml
meta:
  project_name: "my-task"
  created_at: "2026-03-03T12:00:00"
  planning_done: true
  phase: "executing"
  stale_count: 0
  max_stale: 5

tasks:
  - id: investigate_problem
    title: "Read all files in src/ and identify the bug"
    status: completed
    started_at: "2026-03-03T12:01:00"
    completed_at: "2026-03-03T12:02:30"
    notes: "Found null pointer in parser.py line 42"

  - id: fix_bug
    title: "Fix the null pointer bug in parser.py"
    status: pending
    started_at: null
    completed_at: null
    notes: ""
```

Task status flow: `pending` → `in_progress` → `completed`

## Stale Detection

If `checkpoint.yaml` doesn't change for `RELAY_MAX_STALE` consecutive iterations, the runner assumes something is stuck and stops. This prevents infinite loops when Claude fails silently or gets confused.

## Safety

- Phase 2 uses `--dangerously-skip-permissions` for unattended operation
- Run in a sandboxed environment (Docker, VM) for untrusted tasks
- Always review `checkpoint.yaml` and `relay_log.txt` after completion

## Project Structure

```
claude-relay/
├── relay.sh                      # Main runner script
├── skills/
│   └── plan-checkpoint.md        # Phase 1 planning skill
└── templates/
    └── checkpoint.template.yaml  # Reference template
```
