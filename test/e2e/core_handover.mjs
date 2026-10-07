// Jan, 2026-10-07 (q3): after the upgrade Redmine previews pdf, images, text,
// markdown (and textile) itself; the plugin keeps Office, mail, zip and vcard;
// pass and mark-html go off. The rake task does it on the running server; the
// scenario then looks at each kind of file as manager, reporter and outsider,
// at the settings as admin, and restores the seed's settings at the end.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { execSync } from 'node:child_process';
import fs from 'node:fs';

const t = await e2e('core_handover');
const env = { ...process.env, RAILS_ENV: process.env.RMP_SERVER_ENV || 'production' };
const rails = cmd => execSync(cmd, { cwd: process.env.REDMINE_DIR, env, encoding: 'utf8' }).trim();
const key = fs.readFileSync(`${process.env.REDMINE_DIR}/tmp/e2e-manager-api-key`, 'utf8').trim();
const H = { 'X-Redmine-API-Key': key };

await t.anonymous();
const api = async p => (await t.page.request.get(t.BASE + p, { headers: H })).json();
const att = {}, priv = {};
const pub = (await api('/issues.json?project_id=e2e-project&subject=E2E%20previews')).issues[0];
for (const a of (await api(`/issues/${pub.id}.json?include=attachments`)).issue.attachments) att[a.filename] = a.id;
const pi = (await api('/issues.json?project_id=e2e-private&subject=E2E%20private%20previews')).issues[0];
for (const a of (await api(`/issues/${pi.id}.json?include=attachments`)).issue.attachments) priv[a.filename] = a.id;

const dry = rails('bundle exec rake redmine_more_previews:use_core_previews DRY_RUN=1');
const run = rails('bundle exec rake redmine_more_previews:use_core_previews');
const again = rails('bundle exec rake redmine_more_previews:use_core_previews');
if (!/Would switch off: .*peek \.pdf.*pass/.test(dry)) t.problems.push(`dry run: ${dry}`);
if (!/Switched off: .*maggie \.png.*teddie \.txt.*pass/.test(run)) t.problems.push(`run: ${run}`);
if (!/Nothing to change/.test(again)) t.problems.push(`second run: ${again}`);

await t.page.setContent(`<h2>rake redmine_more_previews:use_core_previews</h2><pre>$ DRY_RUN=1\n${dry}\n\n$ (run)\n${run}\n\n$ (again)\n${again}</pre>`);
await t.shot('rake', 'The rake task: dry run lists, the run switches off exactly pdf, images, txt, md, textile, html and the pass converter, a second run changes nothing', { full: false });

await t.login('admin');
await t.go('/settings/plugin/redmine_more_previews');
await t.sudo();
for (const [sel, want] of [['settings[converter][pass][active]', false], ['settings[converter][mark][mime_types][html][active]', false],
  ['settings[converter][peek][mime_types][pdf][active]', false], ['settings[converter][libre][mime_types][docx][active]', true],
  ['settings[converter][cliff][mime_types][eml][active]', true], ['settings[converter][zippy][mime_types][zip][active]', true]]) {
  if ((await t.page.locator(`input[name="${sel}"]`).isChecked()) !== want) t.problems.push(`settings: ${sel} should be ${want ? 'on' : 'off'}`);
}
await t.shot('settings', 'Plugin settings after the task: Pass off, Mark .md/.textile/.html off, Peek, Maggie and Teddie off; Libre, Cliff, Zippy, Vince unchanged');

const core = ['sample.pdf', 'sample.png', 'sample.txt', 'sample.md', 'sample.textile', 'sample.html'];
const plugin = ['sample.docx', 'sample.eml', 'sample.zip', 'sample.vcf'];
for (const user of ['manager', 'reporter']) {
  await t.login(user);
  for (const name of [...core, ...plugin]) {
    await t.go(`/attachments/${att[name]}`, { allow: { js: ['has been blocked by CORS policy'] } });
    const mine = await t.page.locator('#preview_repository_entry_top').count();
    if (core.includes(name) && mine) t.problems.push(`${user} ${name}: still the plugin's preview`);
    if (plugin.includes(name) && !mine) t.problems.push(`${user} ${name}: not the plugin's preview`);
    if (user === 'manager' || name === 'sample.md' || name === 'sample.docx') {
      await t.page.waitForTimeout(1000); await t.page.mouse.move(0, 0);
      const pdfNote = /pdf|docx/.test(name) ? ' (a PDF: headless Chromium has no PDF viewer, so core shows its fallback text and the plugin "Couldn\'t load plugin")' : '';
      await t.shot(`${user}-${name.replace('.', '-')}`, `${user}: ${name} ${core.includes(name) ? 'shown by Redmine 7 itself' : 'still shown by the plugin'}${pdfNote}`, { full: false });
    }
  }
}
await t.login('outsider');
await t.go(`/attachments/${priv['sample.md']}`, { status: 403 });
await t.shot('outsider-refused', 'Outsider on the private project: still 403 (core preview now)', { full: false });
await t.go('/settings/plugin/redmine_more_previews', { status: 403 });
await t.shot('outsider-settings', 'Non-admin on the plugin settings: 403', { full: false });

// back to the seed's settings for the other scenarios
rails(`bundle exec rails runner ${process.cwd()}/test/e2e/seed.rb`);
await t.done();
