# smoke

Run 2026-10-07T16:55:53.966Z against http://127.0.0.1:3000.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](smoke-01.png) | admin | `/` | / (HTTP 200) |
| ![](smoke-02.png) | admin | `/projects/e2e-project` | /projects/e2e-project (HTTP 200) |
| ![](smoke-03.png) | admin | `/projects/e2e-project/issues` | /projects/e2e-project/issues (HTTP 200) |
| ![](smoke-04.png) | admin | `/issues/1` | /issues/1 (HTTP 200) |
| ![](smoke-05.png) | admin | `/projects/e2e-project/issues/new` | /projects/e2e-project/issues/new (HTTP 200) |
| ![](smoke-06.png) | admin | `/projects/e2e-project/settings` | /projects/e2e-project/settings (HTTP 200) |
| ![](smoke-07.png) | admin | `/my/page` | /my/page (HTTP 200) |
| ![](smoke-08.png) | admin | `/my/account` | /my/account (HTTP 200) |
| ![](smoke-09.png) | admin | `/admin` | /admin (HTTP 200) |
| ![](smoke-10.png) | admin | `/admin/plugins` | /admin/plugins (HTTP 200) |
| ![](smoke-11.png) | admin | `/settings/plugin/redmine_more_previews` | /settings/plugin/redmine_more_previews (HTTP 200) |
| ![](smoke-12.png) | admin | `/attachments/1/1` | /attachments/1/1 (HTTP 404) |
| ![](smoke-13.png) | admin | `/attachments/1` | /attachments/1 (HTTP 200) |
| ![](smoke-14.png) | admin | `/admin/info` | /admin/info (HTTP 200) |
| ![](smoke-15.png) | admin | `/attachments/more_preview/1/index` | /attachments/more_preview/1/index (HTTP 404) |
