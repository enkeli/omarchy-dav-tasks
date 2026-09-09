# Security

Nextcloud accounts can expose sensitive personal data. Treat this plugin and its helper as code with access to the user's task list metadata and tasks.

## Credential Handling

- Do not store provider passwords, app-specific passwords, OAuth tokens, or cookies in this repository's files.
- Do not store credentials in `~/.config/omarchy/shell.json`.
- Do not pass credentials through QML IPC payloads.
- Do not log credentials.
- Real provider credentials should be owned by Evolution Data Server, GNOME Online Accounts, or the local desktop keyring.

## Provider Access

The plugin reads and writes task data through local Evolution Data Server APIs. It does not proxy task data through a hosted third-party service.

## Network

All CalDAV traffic goes to the server origin configured during account setup. URLs supplied by the server in responses (item hrefs, principal and calendar-home-set hrefs, redirect targets) are validated against that origin and refused otherwise, and stored credentials are only ever presented to the configured origin. Plain-HTTP URLs are accepted for servers that only offer them, but produce a warning during setup because the password would be sent unencrypted; prefer `https://`.

## Data Stored on Disk

`~/.local/share/omarchy-calendar/` holds the plugin's cache files (`cache.json`, `tasks-cache.json`, `reminders.json`) and `sync.log`. Cache files contain task and calendar metadata, never passwords; they are written atomically with owner-only permissions. `sync.log` is a JSON-lines history of sync activity (calendar names, hostnames, truncated URLs, task uids, sync tokens, and error messages) that rotates to `sync.log.1` once it exceeds 5 MiB. No credentials are written to any of these files.

## Reporting

Report security concerns privately through GitHub's "Report a vulnerability" flow on this repository (Security tab) before public disclosure.
