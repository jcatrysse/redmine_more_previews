// Round 6 (port of curecodejp 9e8df9d, 3b1b73a): with the project module "Redmine More
// Previews" off, the direct preview and asset URLs of attachments and repository files answer
// 404 (they converted before), the pages fall back to Redmine's own; on again, they serve.
import { e2e } from '../../.codex/e2e/lib.mjs';
import fs from 'node:fs';

const REDMINE = process.env.REDMINE_DIR;
const t = await e2e('module_off');
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
async function table(title, intro, rows) {
  await t.page.setContent(`<style>body{font:14px sans-serif;margin:24px}td,th{border:1px solid #ccc;padding:4px 8px;text-align:left}</style>` +
    `<h2>${esc(title)}</h2><p>${esc(intro)}</p><table><tr><th>${rows[0].map(esc).join('</th><th>')}</th></tr>` +
    rows.slice(1).map(r => `<tr><td>${r.map(esc).join('</td><td>')}</td></tr>`).join('') + '</table>');
}
const apiKey = () => ({ 'X-Redmine-API-Key': fs.readFileSync(`${REDMINE}/tmp/e2e-manager-api-key`, 'utf8').trim() });
async function setModule(on) {
  await t.login('admin');
  await t.go('/projects/e2e-project/settings/modules');
  await t.sudo();
  const box = t.page.locator('#project_enabled_module_names_redmine_more_previews');
  if (on) await box.check(); else await box.uncheck();
  await t.page.click('#modules-form input[type=submit], form input[name=commit]');
  await t.settle();
  t.check(`module ${on ? 'on' : 'off'}`);
  await t.login('manager');
}

await t.login('manager');
const issue = (await (await t.page.request.get(`${t.BASE}/issues.json?project_id=e2e-project&subject=E2E%20previews`, { headers: apiKey() })).json()).issues[0];
const att = {};
for (const a of (await (await t.page.request.get(`${t.BASE}/issues/${issue.id}.json?include=attachments`, { headers: apiKey() })).json()).issue.attachments) att[a.filename] = a.id;
const urls = [
  ['zip listing', `/attachments/more_preview/${att['sample.zip']}/index.html`],
  ['zip entry (asset)', `/attachments/more_preview/${att['sample.zip']}/top.txt`],
  ['repository preview', '/projects/e2e-project/repository/samples/preview/sample.txt@/index.txt'],
  ['repository zip entry', '/projects/e2e-project/repository/samples/preview/sample.zip@top.txt'],
];
const rows = [['URL', 'module on', 'module off', 'on again']];
const results = {};
for (const state of ['on', 'off', 'again']) {
  await setModule(state !== 'off');
  for (const [label, url] of urls) {
    const r = await t.page.request.get(t.BASE + url);
    (results[label] ||= []).push(r.status());
  }
  if (state === 'off') {
    await t.go(`/attachments/${att['sample.zip']}`);
    if (await t.page.locator('#preview_pane').count()) t.problems.push('module off: the attachment page still shows the plugin preview');
    await t.shot('page-off', 'Module off: the attachment page is Redmine\'s own (no plugin preview pane)', { full: false });
  }
}
for (const [label, url] of urls) {
  const [on, off, again] = results[label];
  rows.push([`${label}: ${url}`, on, off, again]);
  if (on !== 200 || off !== 404 || again !== 200) t.problems.push(`${label}: ${on}/${off}/${again}, expected 200/404/200`);
}
await table('Direct URLs with the module on, off and on again (manager, browse repository)', 'Upstream 9e8df9d, 3b1b73a: the module switches the direct URLs off too.', rows);
await t.shot('urls', 'The preview and asset URLs answer 404 while the module is off, 200 when it is on', { full: false });
await t.done();
