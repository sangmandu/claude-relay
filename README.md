# claude-relay

Checkpoint-driven autonomous task runner for Claude Code, with **parallel execution** support.

Define a checklist with dependencies, let Claude work through it — running independent tasks concurrently.

## How it works

```
Phase 0 (Session Init)        Phase 1 (Interactive)          Phase 2 (Autonomous)
┌─────────────────────┐       ┌─────────────────────┐       ┌──────────────────────────────────┐
│ Scan checkpoint-*    │       │ User ↔ Claude        │       │ Loop:                            │
│ Resume or new task?  │──────▶│ Build checkpoint     │──────▶│  1. Read checkpoint file          │
│ Name the checkpoint  │       │ together             │       │  2. Find all ready tasks         │
└─────────────────────┘       └─────────────────────┘       │  3. Launch them in parallel      │
                                                             │  4. Wait, mark [x], save yaml   │
                                                             │  5. Repeat until all [x]         │
                                                             └──────────────────────────────────┘
```

- **Phase 0**: Scan existing checkpoint files, decide to resume or start fresh, name the checkpoint
- **Phase 1**: Collaboratively build a task checklist using the `/relay-plan` skill
- **Phase 2**: Claude autonomously works through tasks, running independent ones **in parallel**

## Features

### Named Checkpoints (Session Isolation)

Each relay session gets its own named checkpoint file:

```
checkpoint-onboarding-refactor.yaml
checkpoint-stock-plugin-v2.yaml
checkpoint-db-migration.yaml
```

This solves two critical problems:
- **No accidental overwrites**: Starting a new task won't clobber an in-progress checkpoint from a different task
- **Multiple relays in parallel**: Run separate relay sessions in the same directory without conflict — each operates on its own file

When you start `/relay`, it scans for existing `checkpoint-*.yaml` files and asks whether to resume one or create a new session.

### Parallel Execution with File Locking

Tasks with satisfied dependencies run **concurrently** (up to `RELAY_MAX_PARALLEL`). File-level locking (`fcntl.flock`) prevents race conditions when multiple workers update the checkpoint simultaneously.

### Stop Hook (Auto-Continue)

A built-in Stop Hook prevents Claude from stopping while tasks remain. The hook scans all `checkpoint-*.yaml` files — works across multiple concurrent relay sessions.

### Stale Detection

If the checkpoint doesn't change for `RELAY_MAX_STALE` consecutive iterations, the runner assumes something is stuck and stops.

## vs. claude-ralph

| | claude-relay | claude-ralph |
|---|---|---|
| Parallelism | Concurrent tasks via Agent tool | Sequential only |
| Progress tracking | YAML checkpoint file (inspectable, resumable) | In-memory loop |
| Multi-session | Named checkpoints, multiple relays in same dir | Single loop per session |
| Resume | Pick up where you left off from any session | Start over |
| Planning | Collaborative Phase 1 with dependency graph | Ad-hoc |

## Installation

### Option A: Standalone script

```bash
git clone https://github.com/sangmandu/claude-relay.git
cd claude-relay

# Add to PATH (run from anywhere)
ln -s $(pwd)/relay.sh /usr/local/bin/claude-relay
```

### Option B: Claude Code plugin (--plugin-dir)

```bash
claude --plugin-dir /path/to/claude-relay
```

This loads the relay skills, commands, and hooks into your Claude Code session without needing `relay.sh`.

## Usage

### With relay.sh

```bash
cd ~/projects/my-app

# Interactive — scans existing checkpoints, asks to resume or start new
claude-relay

# Direct — specify checkpoint name
claude-relay . my-task-name
# → uses checkpoint-my-task-name.yaml
```

### Plugin skills

| Skill | Description |
|-------|-------------|
| `/relay` | Full pipeline — Phase 0 → 1 → 2 |
| `/relay-plan` | Build a checkpoint file collaboratively |
| `/relay-run` | Execute pending tasks from an existing checkpoint |
| `/relay-status` | Show status of all checkpoint files |

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `RELAY_MAX_ITER` | 50 | Maximum loop iterations |
| `RELAY_MAX_STALE` | 5 | Stop after N iterations with no checkpoint change |
| `RELAY_MAX_PARALLEL` | 4 | Maximum concurrent tasks per iteration |

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
    depends_on: []
    started_at: "2026-03-03T12:01:00"
    completed_at: "2026-03-03T12:02:30"
    notes: "Found null pointer in parser.py line 42"

  - id: fix_bug
    title: "Fix the null pointer bug in parser.py"
    status: pending
    depends_on: [investigate_problem]
```

Task status flow: `pending` → `in_progress` → `completed` / `failed`

## Parallel Execution

```yaml
tasks:
  # These three run in parallel (no dependencies)
  - id: analyze_frontend
    depends_on: []
  - id: analyze_backend
    depends_on: []
  - id: analyze_database
    depends_on: []

  # This waits for all three
  - id: write_report
    depends_on: [analyze_frontend, analyze_backend, analyze_database]
```

Each parallel task gets its own Claude session and log file in `logs/`.

## Safety

- Phase 2 uses `--dangerously-skip-permissions` for unattended operation
- Run in a sandboxed environment (Docker, VM) for untrusted tasks
- Always review checkpoint files and `logs/` after completion

## Project Structure

```
claude-relay/
├── relay.sh                          # Main runner script
├── skills/
│   ├── relay/SKILL.md                # /relay — full pipeline
│   ├── relay-plan/SKILL.md           # /relay-plan — interactive planning
│   └── relay-run/SKILL.md            # /relay-run — execution only
├── commands/
│   ├── relay-task.md                 # Worker behavior prompt
│   └── relay-status.md               # /relay-status — status display
├── agents/
│   └── relay-orchestrator.md         # Phase 2 orchestrator agent
├── scripts/
│   ├── checkpoint.py                 # Checkpoint CLI with file locking
│   └── relay-stop.sh                 # Stop hook — prevents early exit
└── templates/
    └── checkpoint.template.yaml
```
