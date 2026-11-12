#!/usr/bin/env python3
"""Check that demo-calendars restore puts back the real files and removes demo leftovers.

Runs entirely in a temp directory with a fake Evolution registry, so the live
calendar setup is never touched.
"""

import importlib.machinery
import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("demo_calendars", str(ROOT / "scripts" / "demo-calendars"))
spec = importlib.util.spec_from_loader("demo_calendars", loader)
demo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(demo)


class FakeRegistry:
    def ref_source(self, uid):
        return None


def point_at(root: Path) -> None:
    demo.DATA = root / "data"
    demo.BACKUP = root / "backup"
    demo.STATE = demo.DATA / "demo-state.json"
    demo.MANIFEST = demo.BACKUP / "manifest.json"
    demo.EVO_SOURCES = root / "evo-sources"
    demo.EVO_CALENDARS = root / "evo-calendars"
    demo.EVO_TASKS = root / "evo-tasks"
    demo.registry = lambda: (FakeRegistry(), None)
    demo.adopt_legacy_backup = lambda: False


def fail(message: str) -> None:
    raise SystemExit(f"not ok - {message}")


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    point_at(root)
    demo.DATA.mkdir(parents=True)
    demo.EVO_SOURCES.mkdir()
    (demo.EVO_SOURCES / "omarchy-calendar-caldav-a.source").write_text("[Source]\nEnabled=true\n")
    real_tasks = json.dumps({"tasks": [{"uid": f"t{i}"} for i in range(322)]})
    (demo.DATA / "tasks-cache.json").write_text(real_tasks)
    (demo.DATA / "sync.log").write_text("real log line\n")
    # cache.json and reminders.json deliberately absent: the demo must not leave them behind.

    demo.backup_real()
    manifest = json.loads(demo.MANIFEST.read_text())
    if sorted(manifest["files"]) != ["sync.log", "tasks-cache.json"]:
        fail(f"manifest files: {manifest}")
    if sorted(manifest["absent"]) != ["cache.json", "reminders.json"]:
        fail(f"manifest absent: {manifest}")
    print("ok - backup manifest records existing and absent files")

    # A second seed must not overwrite the real backup with demo state.
    (demo.DATA / "tasks-cache.json").write_text(json.dumps({"tasks": []}))
    demo.backup_real()
    if json.loads((demo.BACKUP / "tasks-cache.json").read_text()) != json.loads(real_tasks):
        fail("second backup overwrote the real tasks cache")
    print("ok - repeat seed keeps the first backup")

    # Simulate the demo run: the shell rewrites the task cache, the seed adds
    # cache.json, the log grows, and a demo calendar folder exists.
    demo.wipe_demo_cache({"Work": "w", "Personal": "p", "Home": "h"})
    if json.loads((demo.DATA / "tasks-cache.json").read_text())["tasks"] != []:
        fail("demo seed left real tasks in the panel cache")
    print("ok - demo seed clears the panel task cache")
    (demo.DATA / "sync.log").write_text("real log line\ndemo line\n")
    demo_uid = "omarchy-calendar-local-demo"
    (demo.EVO_CALENDARS / demo_uid).mkdir(parents=True)
    (demo.EVO_CALENDARS / demo_uid / "calendar.ics").write_text("BEGIN:VCALENDAR\n")
    (demo.EVO_TASKS / demo_uid).mkdir(parents=True)
    (demo.EVO_TASKS / demo_uid / "tasks.ics").write_text("BEGIN:VCALENDAR\n")
    demo.save_state({"disabledCaldav": [], "demoCalendars": [demo_uid], "calendars": {}})

    demo.cmd_restore()

    if json.loads((demo.DATA / "tasks-cache.json").read_text()) != json.loads(real_tasks):
        fail("restore did not put back the real tasks cache")
    if (demo.DATA / "sync.log").read_text() != "real log line\n":
        fail("restore did not put back the real sync log")
    if (demo.DATA / "cache.json").exists() or (demo.DATA / "reminders.json").exists():
        fail("restore left demo-only files in place")
    if (demo.EVO_CALENDARS / demo_uid).exists() or (demo.EVO_TASKS / demo_uid).exists():
        fail("restore left the demo calendar or task folder")
    if demo.STATE.exists() or demo.MANIFEST.exists():
        fail("restore did not clear demo state")
    print("ok - restore puts back real files and removes demo leftovers")

    # After a restore, the next seed should take a fresh backup of the restored state.
    (demo.DATA / "tasks-cache.json").write_text(json.dumps({"tasks": [{"uid": "new"}]}))
    demo.backup_real()
    if json.loads((demo.BACKUP / "tasks-cache.json").read_text()) != {"tasks": [{"uid": "new"}]}:
        fail("backup after restore did not refresh")
    print("ok - backup refreshes after restore")
