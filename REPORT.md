# claude-relay Plugin Refactor — Report

## What Was Refactored

The monolithic `relay.sh` script was decomposed into a proper Claude Code plugin structure. All inline Python heredocs, embedded prompts, and system prompt strings were extracted into standalone, reusable components.

## Before / After

| Aspect | Before | After |
|--------|--------|-------|
| Checkpoint operations | Inline Python heredocs in bash (`locked_python`) | `scripts/checkpoint.py` — standalone CLI with file locking |
| Planning prompt | Hardcoded in `phase1_planning()` | `skills/relay-plan/SKILL.md` — invocable via `/relay-plan` |
| Worker task prompt | Embedded string in `run_single_task()` | `commands/relay-task.md` with argument schema |
| Orchestrator system prompt | Heredoc string in `phase2_execution()` | `agents/relay-orchestrator.md` with frontmatter |
| Status display | None | `commands/relay-status.md` — invocable via `/relay-status` |
| YAML validation | None | `hooks/hooks.json` + `scripts/checkpoint-guard.sh` (PostToolUse hook) |
| Plugin metadata | None | `.claude-plugin/plugin.json` |
| relay.sh | ~500 lines with embedded logic | ~320 lines, delegates to plugin components |

## New Plugin Structure

```
claude-relay/
├── .claude-plugin/
│   └── plugin.json
├── agents/
│   └── relay-orchestrator.md
├── commands/
│   ├── relay-status.md
│   └── relay-task.md
├── hooks/
│   └── hooks.json
├── scripts/
│   ├── checkpoint.py
│   └── checkpoint-guard.sh
├── skills/
│   └── relay-plan/
│       └── SKILL.md
├── templates/
│   └── checkpoint.template.yaml
└── relay.sh
```

## What Works

- **Plugin loads via `--plugin-dir`**: Phase 1 and Phase 2 both pass `--plugin-dir` to claude sessions
- **checkpoint.py CLI**: All 5 commands verified (get_ready_tasks, get_task_field, update_task_status, has_pending, is_planning_done)
- **Parallel execution**: Workers receive plugin via `--plugin-dir`, run independently, report back to orchestrator
- **YAML guard hook**: Validates checkpoint.yaml structure on every Write/Edit
- **End-to-end test**: test-run/ with 3-task pipeline completed successfully

## What Needs Attention

- `skills/plan-checkpoint.md` is a leftover from the old location (superseded by `skills/relay-plan/SKILL.md`) — safe to delete
- `commands/relay-task.md` uses `$ARGUMENTS.*` template variables — requires Claude Code plugin argument interpolation support; the worker prompt in relay.sh still constructs the prompt directly as a fallback
- The `load_system_prompt()` function in relay.sh parses YAML frontmatter with a simple `split('---')` — works for the current agent file but is not a robust YAML parser
- Hook paths use `${CLAUDE_PLUGIN_ROOT}` which requires Claude Code to resolve at runtime
