# admin_info

Run 2026-10-06T20:10:00.500Z against http://127.0.0.1:3000.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](admin_info-info.png) | admin | `/admin/info` | Administration > Information: the converter checks (pandoc, LibreOffice, ImageMagick ...) next to core's own, with SVG check icons |
| ![](admin_info-manager-refused.png) | manager | `/admin/info` | Not for non-admins (403) |
