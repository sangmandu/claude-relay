"""Unit tests for scripts/checkpoint.py"""

import json
import subprocess
import tempfile
import textwrap
from pathlib import Path

import pytest
import yaml

CHECKPOINT_PY = str(Path(__file__).resolve().parent.parent / "scripts" / "checkpoint.py")


def _run(args: list[str], checkpoint_file: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["python3", CHECKPOINT_PY, "-f", checkpoint_file] + args,
        capture_output=True, text=True,
    )


def _write_checkpoint(tmp: Path, data: dict) -> str:
    f = tmp / "checkpoint.yaml"
    f.write_text(yaml.dump(data, default_flow_style=False, allow_unicode=True, sort_keys=False))
    return str(f)


@pytest.fixture
def tmp(tmp_path):
    return tmp_path


class TestGetReadyTasks:
    def test_no_deps_pending(self, tmp):
        ckpt = _write_checkpoint(tmp, {
            "meta": {"planning_done": True},
            "tasks": [
                {"id": "t1", "title": "Task 1", "status": "pending"},
                {"id": "t2", "title": "Task 2", "status": "pending"},
            ],
        })
        r = _run(["get_ready_tasks"], ckpt)
        assert r.returncode == 0
        assert json.loads(r.stdout) == ["t1", "t2"]

    def test_deps_met(self, tmp):
        ckpt = _write_checkpoint(tmp, {
            "meta": {"planning_done": True},
            "tasks": [
                {"id": "t1", "title": "Task 1", "status": "completed"},
                {"id": "t2", "title": "Task 2", "status": "pending", "depends_on": ["t1"]},
            ],
        })
        r = _run(["get_ready_tasks"], ckpt)
        assert json.loads(r.stdout) == ["t2"]

    def test_deps_not_met(self, tmp):
        ckpt = _write_checkpoint(tmp, {
            "meta": {"planning_done": True},
            "tasks": [
                {"id": "t1", "title": "Task 1", "status": "pending"},
                {"id": "t2", "title": "Task 2", "status": "pending", "depends_on": ["t1"]},
            ],
        })
        r = _run(["get_ready_tasks"], ckpt)
        assert json.loads(r.stdout) == ["t1"]

    def test_all_completed(self, tmp):
        ckpt = _write_checkpoint(tmp, {
            "meta": {"planning_done": True},
            "tasks": [
                {"id": "t1", "title": "Task 1", "status": "completed"},
            ],
        })
        r = _run(["get_ready_tasks"], ckpt)
        assert json.loads(r.stdout) == []


class TestUpdateTaskStatus:
    def test_set_in_progress(self, tmp):
        ckpt = _write_checkpoint(tmp, {
            "meta": {"planning_done": True},
            "tasks": [{"id": "t1", "title": "Task 1", "status": "pending"}],
        })
        r = _run(["update_task_status", "t1", "in_progress"], ckpt)
        assert r.returncode == 0
        data = yaml.safe_load(Path(ckpt).read_text())
        assert data["tasks"][0]["status"] == "in_progress"
        assert "started_at" in data["tasks"][0]

    def test_set_completed(self, tmp):
        ckpt = _write_checkpoint(tmp, {
            "meta": {"planning_done": True},
            "tasks": [{"id": "t1", "title": "Task 1", "status": "in_progress"}],
        })
        r = _run(["update_task_status", "t1", "completed"], ckpt)
        assert r.returncode == 0
        data = yaml.safe_load(Path(ckpt).read_text())
        assert data["tasks"][0]["status"] == "completed"
        assert "completed_at" in data["tasks"][0]


class TestHasPending:
    def test_has_pending(self, tmp):
        ckpt = _write_checkpoint(tmp, {
            "meta": {"planning_done": True},
            "tasks": [
                {"id": "t1", "title": "Task 1", "status": "completed"},
                {"id": "t2", "title": "Task 2", "status": "pending"},
            ],
        })
        r = _run(["has_pending"], ckpt)
        assert r.returncode == 0

    def test_all_completed(self, tmp):
        ckpt = _write_checkpoint(tmp, {
            "meta": {"planning_done": True},
            "tasks": [
                {"id": "t1", "title": "Task 1", "status": "completed"},
            ],
        })
        r = _run(["has_pending"], ckpt)
        assert r.returncode == 1

    def test_in_progress_counts(self, tmp):
        ckpt = _write_checkpoint(tmp, {
            "meta": {"planning_done": True},
            "tasks": [
                {"id": "t1", "title": "Task 1", "status": "in_progress"},
            ],
        })
        r = _run(["has_pending"], ckpt)
        assert r.returncode == 0


class TestIsPlanningDone:
    def test_true(self, tmp):
        ckpt = _write_checkpoint(tmp, {"meta": {"planning_done": True}, "tasks": []})
        r = _run(["is_planning_done"], ckpt)
        assert r.returncode == 0

    def test_false(self, tmp):
        ckpt = _write_checkpoint(tmp, {"meta": {"planning_done": False}, "tasks": []})
        r = _run(["is_planning_done"], ckpt)
        assert r.returncode == 1


class TestGetTaskField:
    def test_existing_field(self, tmp):
        ckpt = _write_checkpoint(tmp, {
            "meta": {"planning_done": True},
            "tasks": [{"id": "t1", "title": "My Task", "status": "pending"}],
        })
        r = _run(["get_task_field", "t1", "title"], ckpt)
        assert r.stdout.strip() == "My Task"

    def test_missing_field(self, tmp):
        ckpt = _write_checkpoint(tmp, {
            "meta": {"planning_done": True},
            "tasks": [{"id": "t1", "title": "My Task", "status": "pending"}],
        })
        r = _run(["get_task_field", "t1", "notes"], ckpt)
        assert r.stdout.strip() == ""

    def test_missing_task(self, tmp):
        ckpt = _write_checkpoint(tmp, {
            "meta": {"planning_done": True},
            "tasks": [{"id": "t1", "title": "My Task", "status": "pending"}],
        })
        r = _run(["get_task_field", "t99", "title"], ckpt)
        assert r.stdout.strip() == ""
