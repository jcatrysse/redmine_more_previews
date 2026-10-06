// Who sees a preview: the plugin's only permission is public, so a member
// without special permissions (reporter) previews like the manager; a
// non-member never reaches a private project's attachment, anonymous is sent
// to the login; with the project module off core's own preview is shown.
import { e2e } from '../../.codex/e2e/lib.mjs';
import fs from 'node:fs';

const t = await e2e('permissions');
const key = fs.readFileSync(`${process.env.REDMINE_DIR}/tmp/e2e-manager-api-key`, 'utf8').trim();
const H = { 'X-Redmine-API-Key': key };

await t.anonymous();
const api = async path => (await t.page.request.get(t.BASE + path, { headers: H })).json();
const att = {}, priv = {};
const pub = (await api('/issues.json?project_id=e2e-project&subject=E2E%20previews')).issues[0];
for (const a of (await api(`/issues/${pub.id}.json?include=attachments`)).issue.attachments) att[a.filename] = a.id;
const pi = (await api('/issues.json?project_id=e2e-private&subject=E2E%20private%20previews')).issues[0];
for (const a of (await api(`/issues/${pi.id}.json?include=attachments`)).issue.attachments) priv[a.filename] = a.id;

await t.login('reporter');
await t.go(`/attachments/${att['sample.md']}`);
if (!(await t.page.locator('#preview_pane').count())) t.problems.push('reporter: no preview');
await t.page.waitForTimeout(1000); await t.page.mouse.move(0, 0);
await t.shot('reporter', 'Reporter (core role, no extra permissions) sees the markdown preview: the plugin permission is public', { full: false });

await t.login('manager');
await t.go(`/attachments/${priv['sample.md']}`);
if (!(await t.page.locator('#preview_pane').count())) t.problems.push('manager: no preview in the private project');
await t.page.waitForTimeout(1000); await t.page.mouse.move(0, 0);
await t.shot('manager-private', 'Manager, member of the private project, sees the preview there', { full: false });

await t.login('outsider');
await t.go(`/attachments/${priv['sample.md']}`, { status: 403 });
await t.shot('outsider-page', 'Outsider (no membership): the private attachment is refused (403)', { full: false });
for (const u of [`/attachments/more_preview/${priv['sample.md']}/index.html`, `/attachments/more_preview/${priv['sample.md']}/index.html?asset=x.png`]) {
  const r = await t.page.request.get(t.BASE + u);
  if (r.status() !== 403) t.problems.push(`outsider ${u}: HTTP ${r.status()}`);
}
await t.anonymous();
await t.go(`/attachments/${priv['sample.md']}`);
if (!t.page.url().includes('/login')) t.problems.push(`anonymous: ${t.page.url()}`);
await t.shot('anonymous', 'Anonymous on the private attachment is sent to the login', { full: false });

// project module off: core's preview, the plugin's URL still refuses nothing it should not
await t.login('admin');
await t.go('/projects/e2e-private/settings/modules');
await t.sudo();
await t.page.uncheck('#project_enabled_module_names_redmine_more_previews');
await t.page.click('#modules-form input[type=submit], form input[name=commit]');
await t.settle();
t.check('module off');
await t.login('manager');
await t.go(`/attachments/${priv['sample.md']}`);
if (await t.page.locator('#preview_pane').count()) t.problems.push('module off: plugin preview still shown');
await t.shot('module-off', 'Module "Redmine More Previews" off in the private project: Redmine 7 shows its own markdown preview', { full: false });
await t.login('admin');
await t.go('/projects/e2e-private/settings/modules');
await t.sudo();
await t.page.check('#project_enabled_module_names_redmine_more_previews');
await t.page.click('#modules-form input[type=submit], form input[name=commit]');
await t.settle();
t.check('module on');
await t.shot('module-on', 'Module switched on again in the project settings (admin)', { full: false });
await t.done();
