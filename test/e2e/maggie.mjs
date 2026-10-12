// Maggie turned on for pdf and png (Jan, 2026-10-11, port of curecodejp e58d928):
// PostScript disguised as a PDF gets no preview (it never reaches ImageMagick
// or Ghostscript), a real PDF and a PNG still convert. The settings are set
// through rails runner and restored from the seed at the end.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { execSync } from 'node:child_process';
import fs from 'node:fs';

const t = await e2e('maggie');
const env = { ...process.env, RAILS_ENV: process.env.RMP_SERVER_ENV || 'production' };
const rails = cmd => execSync(cmd, { cwd: process.env.REDMINE_DIR, env, encoding: 'utf8' }).trim();
const H = { 'X-Redmine-API-Key': fs.readFileSync(`${process.env.REDMINE_DIR}/tmp/e2e-manager-api-key`, 'utf8').trim() };

// Maggie owns .pdf (to png) and .png (to jpg); Peek off for .pdf
rails(`bundle exec rails runner "s = Setting.plugin_redmine_more_previews.to_h.deep_dup; ` +
  `s['converter']['peek']['mime_types']['pdf']['active'] = '0'; ` +
  `s['converter']['maggie']['mime_types']['pdf'] = { 'active' => '1', 'format' => 'png' }; ` +
  `Setting.plugin_redmine_more_previews = s"`);

await t.anonymous();
const issue = (await (await t.page.request.get(`${t.BASE}/issues.json?project_id=e2e-project&subject=E2E%20previews`, { headers: H })).json()).issues[0];
const marker = `/tmp/rmp-maggie-${Date.now()}`;
const evil = `/a 1 def\n%PDF-1.4\n(${marker}) (w) file closefile\nshowpage\n`;
const up = await t.page.request.post(`${t.BASE}/uploads.json?filename=disguised.pdf`, {
  headers: { ...H, 'Content-Type': 'application/octet-stream' }, data: Buffer.from(evil) });
const token = (await up.json()).upload.token;
await t.page.request.put(`${t.BASE}/issues/${issue.id}.json`, { headers: { ...H, 'Content-Type': 'application/json' },
  data: { issue: { uploads: [{ token, filename: 'disguised.pdf', content_type: 'application/pdf' }] } } });
const att = {};
for (const a of (await (await t.page.request.get(`${t.BASE}/issues/${issue.id}.json?include=attachments`, { headers: H })).json()).issue.attachments) att[a.filename] = a.id;

await t.login('admin');
await t.go('/settings/plugin/redmine_more_previews');
await t.sudo();
if (!(await t.page.locator('input[name="settings[converter][maggie][mime_types][pdf][active]"]').isChecked())) t.problems.push('maggie .pdf not active');
await t.page.locator('#converter_maggie').scrollIntoViewIfNeeded();
await t.shot('settings', 'Maggie turned on for .pdf (to png) and .png (to jpg), Peek off for .pdf', { full: false });

for (const user of ['manager', 'reporter']) {
  await t.login(user);
  const results = [];
  for (const [name, fmt, magic] of [['disguised.pdf', 'png', null], ['sample.pdf', 'png', '\x89PNG'], ['sample.png', 'jpg', '\xFF\xD8']]) {
    const r = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att[name]}/index.${fmt}?reload=1`);
    const head = (await r.body()).toString('latin1').slice(0, 4);
    results.push(`${r.status()} ${name} -> index.${fmt}: ${head ? JSON.stringify(head) : '(empty)'}`);
    if (magic && !head.startsWith(magic)) t.problems.push(`${user} ${name}: not converted (${head})`);
    if (!magic && (head.startsWith('\x89PNG') || head.startsWith('%PDF'))) t.problems.push(`${user} disguised.pdf: a preview came back`);
    // a conversion without output is answered with 404 since round 5 (curecodejp 32b9e77)
    if (!magic && r.status() !== 404) t.problems.push(`${user} disguised.pdf: HTTP ${r.status()}, expected 404`);
  }
  if (fs.existsSync(marker)) t.problems.push(`${user}: the PostScript in disguised.pdf ran (${marker} exists)`);
  for (const name of ['disguised.pdf', 'sample.pdf', 'sample.png']) {
    await t.go(`/attachments/${att[name]}`, { allow: name === 'disguised.pdf' ? { requests: [`404 image /attachments/more_preview/${att[name]}/index.png`] } : {} });
    await t.page.waitForTimeout(1000); await t.page.mouse.move(0, 0);
    await t.shot(`${user}-${name.replace('.', '-')}`, `${user}: ${name} ${name === 'disguised.pdf' ? 'gets no preview: PostScript disguised as a PDF never reaches ImageMagick' : 'still converted by Maggie'}`, { full: false });
  }
  await t.page.setContent(`<h2>Maggie conversions as ${user}</h2><pre>${results.join('\n')}\n\nmarker file written by the PostScript: ${fs.existsSync(marker) ? 'YES' : 'no'}</pre>`);
  await t.shot(`${user}-results`, `${user}: the disguised PDF returns no image, the real PDF a PNG, the PNG a JPEG`, { full: false });
}
await t.login('outsider');
await t.go(`/attachments/${att['disguised.pdf']}`, { allow: { requests: [`404 image /attachments/more_preview/${att['disguised.pdf']}/index.png`] } }); // public project: outsider may see attachments
await t.shot('outsider', 'outsider (non-member, public project): same result, no preview of the disguised PDF', { full: false });

// clean up: remove the upload, restore the seed's settings
await t.page.request.delete(`${t.BASE}/attachments/${att['disguised.pdf']}.json`, { headers: H });
rails(`bundle exec rails runner ${process.cwd()}/test/e2e/seed.rb`);
await t.done();
