# permissions

Run 2026-10-07T16:52:35.168Z against http://127.0.0.1:3000.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](permissions-reporter.png) | reporter | `/attachments/6` | Reporter (core role, no extra permissions) sees the markdown preview: the plugin permission is public |
| ![](permissions-manager-private.png) | manager | `/attachments/17` | Manager, member of the private project, sees the preview there |
| ![](permissions-outsider-page.png) | outsider | `/attachments/17` | Outsider (no membership): the private attachment is refused (403) |
| ![](permissions-anonymous.png) | anonymous | `/login?back_url=http%3A%2F%2F127.0.0.1%3A3000%2Fattachments%2F17` | Anonymous on the private attachment is sent to the login |
| ![](permissions-module-settings-error.png) | admin | `/projects/e2e-private/settings/modules` | Project settings could not be opened, so the module was not switched (see the problems of this run) |

## Problems

- /projects/e2e-private/settings/modules as admin: HTTP 500, expected 200
- project settings > modules unavailable (HTTP error page), module not switched off
