# Agent instructions

- This is a standalone Omarchy plugin (`dev.enkeli.omarchy-dav-tasks`), not an Omarchy core checkout; do not edit `/usr/share/omarchy`.
- Runtime entry points are `Service.qml` (service) and `BarWidget.qml` (bar widget), declared in `manifest.json`; `Panel.qml` owns the popup and `TasksView.qml` owns its task/config views.
- Keep provider and process logic in `Service.qml`/`helper/omarchy-calendar-helper`, not in QML presentation code; normalize provider data before exposing it to QML.
- Credentials must stay in the system keyring/stdin flow; never put them in plugin settings, source, logs, or tests.
- Use shared `qs.Commons`/`qs.Ui` components and `Color`/`Style` theme roles for UI. The custom `qs.Ui.Button` uses flat properties such as `fontFamily`; do not use unsupported Qt Quick Controls grouped properties like `font.family` on it.
- Use two-space indentation for QML, JavaScript, JSON, and shell files; shell scripts require `#!/bin/bash`.
- Run the full verification suite with `./test/all`; it runs helper, QML static, CalDAV harness, optional write, and Node model tests in that order.
- Focused checks are `bash test/helper-test.sh`, `bash test/qml-test.sh`, `python3 test/caldav-harness.py`, `bash test/write-test.sh`, and `node test/task-model-test.js`.
- The EDS write test is skipped unless `OMARCHY_CALENDAR_WRITE_TEST=1`; enabling it performs real temporary EDS writes and cleanup.
- Validate plugin packaging with `omarchy plugin validate .`; UI changes require a running Omarchy session for behavioral verification.
- For UI demos, use `python3 scripts/demo-calendars seed`, restart the shell, then restore with `python3 scripts/demo-calendars restore` and restart again; seed backs up real data under `~/.local/share/omarchy-calendar/demo-backup`.
- Release versions are stored in `manifest.json`; follow the repository release guidance in `CONTRIBUTING.md` and keep the manifest version aligned with release tags (`vX.Y.Z`).
