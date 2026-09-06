# Security

Nextcloud accounts can expose sensitive personal data. Treat this plugin and its helper as code with access to the user's task list metadata and tasks.

## Credential Handling

- Do not store provider passwords, app-specific passwords, OAuth tokens, or cookies in this repository's files.
- Do not store credentials in `~/.config/omarchy/shell.json`.
- Do not pass credentials through QML IPC payloads.
- Do not log credentials.
- Real provider credentials should be owned by Evolution Data Server, GNOME Online Accounts, or the local desktop keyring.

## Provider Access

The plugin should read and write task data through local Evolution Data Server APIs. It should not proxy task data through a hosted third-party service.

## Reporting

For now, report security concerns privately to the repository owner before public disclosure. This file should be updated with a public contact before release.
