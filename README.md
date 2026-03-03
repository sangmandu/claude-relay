# claude-relay

Checkpoint-driven autonomous task runner for Claude Code, with **parallel execution** support.

Define a checklist with dependencies, let Claude work through it — running independent tasks concurrently.

## How it works

```
Phase 1 (Interactive)          Phase 2 (Autonomous)
┌─────────────────────┐       ┌──────────────────────────────────┐
│ User ↔ Claude        │       │ Loop:                            │
│ Build checkpoint.yaml│──────▶│  1. Read checkpoint.yaml         │
│ together             │       │  2. Find all ready tasks         │
└─────────────────────┘       │  3. Launch them in parallel      │
                               │  4. Wait, mark [x], save yaml   │
                               │  5. Repeat until all [x]         │
                               └──────────────────────────────────┘
```

- **Phase 1**: You and Claude collaboratively build a task checklist (`checkpoint.yaml`)
- **Phase 2**: Claude autonomously works through tasks, running independent ones **in parallel**, updating yaml after each completion

`checkpoint.yaml` tracks progress as a file so you always know where things stand.

## Installation

```bash
# Clone
git clone https://github.com/sangmandu/claude-relay.git
cd claude-relay

# Add to PATH (run from anywhere)
ln -s $(pwd)/relay.sh /usr/local/bin/claude-relay
```

## Usage

```bash
cd ~/projects/my-app
claude-relay
```

That's it. Phase 1 starts an interactive session to build your checklist, then Phase 2 runs autonomously.

If you already have a `checkpoint.yaml` with `planning_done: true`, Phase 1 is skipped and execution begins immediately.

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `RELAY_MAX_ITER` | 50 | Maximum loop iterations |
| `RELAY_MAX_STALE` | 5 | Stop after N iterations with no checkpoint change |
| `RELAY_MAX_PARALLEL` | 4 | Maximum concurrent tasks per iteration |

```bash
RELAY_MAX_ITER=100 RELAY_MAX_PARALLEL=6 claude-relay
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
    depends_on: []
    started_at: "2026-03-03T12:01:00"
    completed_at: "2026-03-03T12:02:30"
    notes: "Found null pointer in parser.py line 42"

  - id: fix_bug
    title: "Fix the null pointer bug in parser.py"
    status: pending
    depends_on: [investigate_problem]
    started_at: null
    completed_at: null
    notes: ""
```

Task status flow: `pending` → `in_progress` → `completed`

## Parallel Execution

Tasks with satisfied dependencies (or no dependencies) run **concurrently**, up to `RELAY_MAX_PARALLEL` at a time.

```yaml
tasks:
  # These three run in parallel (no dependencies)
  - id: analyze_frontend
    title: "Analyze frontend code"
    depends_on: []

  - id: analyze_backend
    title: "Analyze backend code"
    depends_on: []

  - id: analyze_database
    title: "Analyze database schema"
    depends_on: []

  # This waits for all three to finish
  - id: write_report
    title: "Write combined analysis report"
    depends_on: [analyze_frontend, analyze_backend, analyze_database]
```

Each parallel task gets its own Claude session and log file in `logs/`.

File locking prevents race conditions when multiple tasks update `checkpoint.yaml` simultaneously.

## Stale Detection

If `checkpoint.yaml` doesn't change for `RELAY_MAX_STALE` consecutive iterations, the runner assumes something is stuck and stops.

## Logs

Each task gets an individual log file:

```
logs/
├── analyze_frontend_20260303_120100.log
├── analyze_backend_20260303_120100.log
└── write_report_20260303_120230.log
```

## Safety

- Phase 2 uses `--dangerously-skip-permissions` for unattended operation
- Run in a sandboxed environment (Docker, VM) for untrusted tasks
- Always review `checkpoint.yaml` and `logs/` after completion

## Project Structure

```
claude-relay/
├── relay.sh                      # Main runner script
├── skills/
│   └── plan-checkpoint.md        # Phase 1 planning skill
└── templates/
    └── checkpoint.template.yaml  # Reference template
```
