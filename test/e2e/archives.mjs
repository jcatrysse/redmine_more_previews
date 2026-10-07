// Zippy: files inside a zip, tar and tgz attachment are listed and can be
// downloaded from the (sandboxed) preview, also from a folder.
import { e2e } from '../../.codex/e2e/lib.mjs';
import fs from 'node:fs';

const t = await e2e('archives');
await t.login('reporter'); // member without any special permission: the plugin's permission is public

const issues = await (await t.page.request.get(`${t.BASE}/issues.json?project_id=e2e-project&subject=E2E%20previews`, { headers: e2eApiKey() })).json();
const att = {};
for (const a of (await (await t.page.request.get(`${t.BASE}/issues/${issues.issues[0].id}.json?include=attachments`, { headers: e2eApiKey() })).json()).issue.attachments) att[a.filename] = a.id;

// zip: the table is an HTML preview in an <object>; click the file in the folder
await t.go(`/attachments/${att['sample.zip']}`);
const frame = t.page.frames().find(f => f.url().includes(`/attachments/more_preview/${att['sample.zip']}/index.html`));
if (!frame) t.problems.push('zip: preview document not found');
else {
  const href = await frame.locator('a', { hasText: 'hello.txt' }).getAttribute('href');
  if (!href.endsWith('asset=inner%2Fhello.txt')) t.problems.push(`zip: link ${href} (encoded twice?)`);
  const [download] = await Promise.all([t.page.waitForEvent('download', { timeout: 10000 }).catch(() => null),
    frame.locator('a', { hasText: 'hello.txt' }).click()]);
  if (!download) t.problems.push('zip: clicking hello.txt in the sandboxed preview started no download');
  else {
    const body = (await import('node:fs')).readFileSync(await download.path(), 'utf8');
    if (body !== 'hello inner\n') t.problems.push(`zip: downloaded "${body}"`);
    if (download.suggestedFilename() !== 'hello.txt') t.problems.push(`zip: file name ${download.suggestedFilename()}`);
  }
  t.check('zip download');
}
await t.page.mouse.move(0, 0);
await t.shot('zip', 'Zip listing with the folder "inner"; clicking inner/hello.txt in the sandboxed preview downloads "hello inner" (was an empty file before this branch)', { full: false });

// tar inline: the table is in the page itself
await t.go(`/attachments/${att['sample.tar']}`);
const [tarDownload] = await Promise.all([t.page.waitForEvent('download', { timeout: 10000 }).catch(() => null),
  t.page.locator('#preview_repository_entry_top + div a', { hasText: 'hello.txt' }).click()]);
if (!tarDownload) t.problems.push('tar: no download');
else if ((await import('node:fs')).readFileSync(await tarDownload.path(), 'utf8') !== 'hello inner\n') t.problems.push('tar: wrong content');
t.check('tar download');
await t.shot('tar', 'Tar listing rendered inline; inner/hello.txt downloads its content', { full: false });

// tgz: top level file through its URL
for (const [name, asset, want] of [['sample.tgz', 'top.txt', 'top level\n'], ['sample.tgz', 'inner%2Fhello.txt', 'hello inner\n'], ['sample.zip', 'top.txt', 'top level\n']]) {
  const res = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att[name]}/index.html?asset=${asset}`);
  const body = await res.text();
  if (res.status() !== 200 || body !== want) t.problems.push(`${name} ${asset}: HTTP ${res.status()} "${body.slice(0, 40)}"`);
  if (!(res.headers()['content-disposition'] || '').startsWith('attachment')) t.problems.push(`${name} ${asset}: not served as a download`);
}
await t.go(`/attachments/${att['sample.tgz']}`);
await t.page.mouse.move(0, 0);
await t.shot('tgz', 'Tgz listing; top.txt and inner/hello.txt served as downloads with their content (checked through their URLs)', { full: false });
await t.done();

// lookups through the manager's API key (test/e2e/seed.rb): a plugin may restrict issue data for a session
function e2eApiKey() {
  return { 'X-Redmine-API-Key': fs.readFileSync(`${process.env.REDMINE_DIR}/tmp/e2e-manager-api-key`, 'utf8').trim() };
}
