---
name: relay-help
description: Show usage guide for claude-relay plugin
disable-model-invocation: true
---

# claude-relay — Usage Guide

## Commands

| Command | What it does |
|---------|-------------|
| `/relay` | **Full pipeline**: plan tasks with you → execute all autonomously |
| `/relay-plan` | **Plan only**: collaboratively build checkpoint.yaml |
| `/relay-run` | **Execute only**: run pending tasks from existing checkpoint.yaml |
| `/relay-status` | **Check progress**: show formatted task status table |
| `/relay-help` | This guide |

## Typical Workflow

```
/relay          ← just use this, it handles everything
```

1. You describe what you want done
2. Claude breaks it into tasks, you refine together
3. Claude executes all tasks autonomously (parallel when possible)
4. Done!

## Advanced: Split Planning and Execution

```
/relay-plan     ← build the plan, stop there
                   (review checkpoint.yaml, edit manually if needed)
/relay-run      ← execute the plan
/relay-status   ← check progress anytime
```

## How It Works

- Tasks are tracked in `checkpoint.yaml` in your working directory
- Tasks with no dependencies run **in parallel** (up to 4 concurrent)
- Tasks with `depends_on` wait for dependencies to complete first
- Progress survives interruptions — just run `/relay-run` to resume

## Configuration

Set these in checkpoint.yaml `meta` section or as environment variables:

| Setting | Default | Description |
|---------|---------|-------------|
| `RELAY_MAX_PARALLEL` | 4 | Max concurrent parallel tasks |

## Shell Script (Optional)

For CI/CD or running outside Claude Code:
```bash
claude-relay ./my-project    # requires: sudo ln -sf ~/claude-relay/relay.sh /usr/local/bin/claude-relay
```
