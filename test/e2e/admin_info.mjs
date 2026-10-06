// Administration > Information lists the external programs the converters need.
import { e2e } from '../../.codex/e2e/lib.mjs';

const t = await e2e('admin_info');
await t.login('admin');
await t.go('/admin/info');
await t.sudo();
const text = await t.page.locator('#content').innerText();
for (const s of ['pandoc', 'LibreOffice', 'ImageMagick']) if (!new RegExp(s, 'i').test(text)) t.problems.push(`admin info lacks ${s}`);
await t.shot('info', 'Administration > Information: the converter checks (pandoc, LibreOffice, ImageMagick ...) next to core\'s own, with SVG check icons');
await t.login('manager');
await t.go('/admin/info', { status: 403 });
await t.shot('manager-refused', 'Not for non-admins (403)', { full: false });
await t.done();
