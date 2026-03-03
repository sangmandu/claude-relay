#!/usr/bin/env python3
"""CLI module for checkpoint.yaml operations with file locking."""

import argparse
import fcntl
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import yaml


def _lock_and_load(checkpoint_file: str, *, write=False):
    path = Path(checkpoint_file)
    if not path.exists():
        print(f"Error: {checkpoint_file} not found", file=sys.stderr)
        sys.exit(1)
    fh = open(path, "r+" if write else "r")
    fcntl.flock(fh, fcntl.LOCK_EX)
    data = yaml.safe_load(fh)
    if write:
        return fh, data
    else:
        fh.close()
        return data


def _write_and_unlock(fh, data):
    fh.seek(0)
    fh.truncate()
    yaml.dump(data, fh, default_flow_style=False, allow_unicode=True, sort_keys=False)
    fh.close()


def cmd_get_ready_tasks(args):
    data = _lock_and_load(args.file)
    tasks = data.get("tasks", [])
    completed = {t["id"] for t in tasks if t.get("status") == "completed"}
    ready = []
    for t in tasks:
        if t.get("status") != "pending":
            continue
        deps = t.get("depends_on", [])
        if all(d in completed for d in deps):
            ready.append(t["id"])
    print(json.dumps(ready))


def cmd_get_task_field(args):
    data = _lock_and_load(args.file)
    for t in data.get("tasks", []):
        if t["id"] == args.task_id:
            print(t.get(args.field, ""))
            return
    print("")


def cmd_update_task_status(args):
    fh, data = _lock_and_load(args.file, write=True)
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    for t in data.get("tasks", []):
        if t["id"] == args.task_id:
            t["status"] = args.status
            if args.status == "in_progress":
                t["started_at"] = timestamp
            elif args.status == "completed":
                t["completed_at"] = timestamp
            break
    _write_and_unlock(fh, data)


def cmd_has_pending(args):
    data = _lock_and_load(args.file)
    for t in data.get("tasks", []):
        if t.get("status") in ("pending", "in_progress"):
            sys.exit(0)
    sys.exit(1)


def cmd_is_planning_done(args):
    data = _lock_and_load(args.file)
    if data.get("meta", {}).get("planning_done") is True:
        sys.exit(0)
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Checkpoint.yaml CLI")
    parser.add_argument("--file", "-f", default="checkpoint.yaml", help="Path to checkpoint.yaml")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("get_ready_tasks", help="Print JSON list of task IDs whose deps are met")

    p = sub.add_parser("get_task_field", help="Print a field value for a task")
    p.add_argument("task_id")
    p.add_argument("field")

    p = sub.add_parser("update_task_status", help="Update a task's status")
    p.add_argument("task_id")
    p.add_argument("status", choices=["pending", "in_progress", "completed", "failed"])

    sub.add_parser("has_pending", help="Exit 0 if pending/in_progress tasks exist, else 1")

    sub.add_parser("is_planning_done", help="Exit 0 if planning_done is true, else 1")

    args = parser.parse_args()
    commands = {
        "get_ready_tasks": cmd_get_ready_tasks,
        "get_task_field": cmd_get_task_field,
        "update_task_status": cmd_update_task_status,
        "has_pending": cmd_has_pending,
        "is_planning_done": cmd_is_planning_done,
    }
    commands[args.command](args)


if __name__ == "__main__":
    main()
