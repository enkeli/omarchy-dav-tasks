#!/usr/bin/env python3
"""Unit tests for the edit-task VTODO rewrite (no server or EDS needed)."""
import importlib.machinery
import importlib.util
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
loader = importlib.machinery.SourceFileLoader("calendar_helper", str(root / "helper/omarchy-calendar-helper"))
spec = importlib.util.spec_from_loader("calendar_helper", loader)
helper = importlib.util.module_from_spec(spec)
sys.modules["calendar_helper"] = helper
loader.exec_module(helper)

SOURCE = "\r\n".join([
    "BEGIN:VCALENDAR", "BEGIN:VTODO", "UID:x1", "SUMMARY:Old", "DESCRIPTION:old desc",
    "DTSTART:20261101T000000Z", "DUE:20261110T000000Z", "CATEGORIES:a,b", "PRIORITY:3",
    "STATUS:NEEDS-ACTION", "X-KEEP:yes",
    "BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:alarm text", "END:VALARM",
    "END:VTODO", "END:VCALENDAR", ""])


def lines(doc):
    return doc.replace("\r\n", "\n").split("\n")


# payload parsing
edits = helper.parse_task_edit_payload('{"title":" New ","description":"","due":"2026-10-30","categories":"x, y","priority":12}')
assert edits == {"title": "New", "description": "", "due": "2026-10-30", "categories": ["x", "y"], "priority": 9}, edits
for bad in ('{}', '[]', 'nope', '{"title":"  "}'):
    try:
        helper.parse_task_edit_payload(bad)
    except ValueError:
        pass
    else:
        raise SystemExit(f"not ok - payload {bad!r} should be rejected")

# only the supplied fields change; everything else survives
out = lines(helper.vtodo_edited_document(SOURCE, {"description": "hi"}))
assert "DESCRIPTION:hi" in out and "SUMMARY:Old" in out and "X-KEEP:yes" in out
assert "DTSTART:20261101T000000Z" in out and "DUE:20261110T000000Z" in out and "CATEGORIES:a,b" in out
assert any(line.startswith("LAST-MODIFIED:") for line in out)

# the VALARM's own DESCRIPTION is never touched or removed
assert "DESCRIPTION:alarm text" in out
out = lines(helper.vtodo_edited_document(SOURCE, {"description": ""}))
assert "DESCRIPTION:alarm text" in out and "DESCRIPTION:old desc" not in out

# clearing and replacing, with escaping
out = lines(helper.vtodo_edited_document(SOURCE, edits))
assert "SUMMARY:New" in out and "DUE:20261030T000000Z" in out and "CATEGORIES:x,y" in out
assert not any(line.startswith("PRIORITY") for line in out) or "PRIORITY:9" in out
assert not any(line.startswith("DESCRIPTION:old") for line in out)
out = lines(helper.vtodo_edited_document(SOURCE, {"title": "A; B, C"}))
assert "SUMMARY:A\\; B\\, C" in out

# a due date at or before DTSTART drops the stored DTSTART (strict servers)
out = lines(helper.vtodo_edited_document(SOURCE, {"due": "2026-10-30"}))
assert not any(line.startswith("DTSTART") for line in out)
out = lines(helper.vtodo_edited_document(SOURCE, {"due": "2026-12-30"}))
assert "DTSTART:20261101T000000Z" in out and "DUE:20261230T000000Z" in out

# clearing the due date and categories
out = lines(helper.vtodo_edited_document(SOURCE, {"due": "", "categories": [], "priority": 0}))
assert not any(line.startswith(("DUE", "CATEGORIES", "PRIORITY")) for line in out)

# properties missing from the source are inserted before END:VTODO
bare = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:x2\r\nSUMMARY:S\r\nEND:VTODO\r\nEND:VCALENDAR\r\n"
out = lines(helper.vtodo_edited_document(bare, {"categories": ["z"], "priority": 2}))
assert out.index("CATEGORIES:z") < out.index("END:VTODO") and "PRIORITY:2" in out

# starts-by (DTSTART): payload parsing, set, move and clear
edits = helper.parse_task_edit_payload('{"dtstart":"2026-10-01"}')
assert edits == {"dtstart": "2026-10-01"}, edits
out = lines(helper.vtodo_edited_document(SOURCE, {"dtstart": "2026-10-05"}))
assert "DTSTART:20261005T000000Z" in out and "DUE:20261110T000000Z" in out
assert not any(line == "DTSTART:20261101T000000Z" for line in out)
out = lines(helper.vtodo_edited_document(SOURCE, {"dtstart": ""}))
assert not any(line.startswith("DTSTART") for line in out) and "DUE:20261110T000000Z" in out
# a start on or after the due date is refused (stored or edited due)
for edit in ({"dtstart": "2026-11-10"}, {"dtstart": "2026-12-01"}):
    try:
        helper.vtodo_edited_document(SOURCE, edit)
    except ValueError as error:
        assert "Starts by" in str(error)
    else:
        raise SystemExit(f"not ok - start {edit} at/after due should be refused")
try:
    helper.vtodo_edited_document(SOURCE, {"dtstart": "2026-10-20", "due": "2026-10-15"})
except ValueError:
    pass
else:
    raise SystemExit("not ok - start after edited due should be refused")
# an explicit start wins over the due-date repair that drops a stored DTSTART
out = lines(helper.vtodo_edited_document(SOURCE, {"due": "2026-10-30", "dtstart": "2026-10-10"}))
assert "DTSTART:20261010T000000Z" in out and "DUE:20261030T000000Z" in out

print("ok - helper edit-task rewrite")
