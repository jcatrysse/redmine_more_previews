// Cliff: a mail attachment shows its headers above the body, all header fields
// behind "...", "Unsafe reload" converts without the cache; a mail whose subject
// and body carry HTML is shown as text and runs nothing.
import { e2e } from '../../.codex/e2e/lib.mjs';

const t = await e2e('mail');
await t.login('manager');
const issues = await (await t.page.request.get(`${t.BASE}/issues.json?project_id=e2e-project&subject=E2E%20previews`)).json();
const issueId = issues.issues[0].id;
const att = {};
for (const a of (await (await t.page.request.get(`${t.BASE}/issues/${issueId}.json?include=attachments`)).json()).issue.attachments) att[a.filename] = a.id;

await t.go(`/attachments/${att['sample.eml']}`);
const box = await t.page.locator('#preview_repository_entry_top .box').first().innerText();
for (const s of ['alice@example.net', 'bob@example.net', 'Sample mail for the preview']) if (!box.includes(s)) t.problems.push(`headers lack ${s}`);
await t.page.locator('#preview_repository_entry_top a.collapsible', { hasText: '...' }).click();
await t.page.waitForTimeout(500);
if (!(await t.page.locator('#preview_repository_entry_top', { hasText: 'Message-ID' }).count())) t.problems.push('header fields not shown');
await t.page.mouse.move(0, 0);
await t.shot('headers', 'Mail preview: header box, all header fields opened with "...", the body below; Update and Unsafe reload with their icons', { full: false });

await t.page.click('#content a.icon-warning');
await t.settle();
if (!/reload=1/.test(t.page.url()) || !/unsafe=1/.test(t.page.url())) t.problems.push(`unsafe reload: ${t.page.url()}`);
t.check('unsafe reload');
await t.page.mouse.move(0, 0);
await t.shot('unsafe-reload', '"Unsafe reload" converts the mail again without the cache', { full: false });

// a hostile mail, uploaded through the REST API as the manager
const fs = await import('node:fs');
const mail = fs.readFileSync('test/fixtures/files/sample.eml', 'utf8')
  .replace('Subject: Sample mail for the preview', 'Subject: <img src=x onerror="document.title=\'pwned\'"> hostile')
  .replace('this is the body', '<script>document.title="pwned"</script><b>bold?</b> this is the body');
const up = await t.page.request.post(`${t.BASE}/uploads.json?filename=hostile.eml`, {
  headers: { 'Content-Type': 'application/octet-stream', 'X-Redmine-API-Key': await apiKey() }, data: Buffer.from(mail) });
const token = (await up.json()).upload.token;
const put = await t.page.request.put(`${t.BASE}/issues/${issueId}.json`, {
  headers: { 'Content-Type': 'application/json', 'X-Redmine-API-Key': await apiKey() },
  data: { issue: { uploads: [{ token, filename: 'hostile.eml', content_type: 'message/rfc822' }] } } });
if (put.status() !== 204) t.problems.push(`attach hostile mail: HTTP ${put.status()}`);
const atts = (await (await t.page.request.get(`${t.BASE}/issues/${issueId}.json?include=attachments`)).json()).issue.attachments;
const hostile = atts.filter(a => a.filename === 'hostile.eml').pop();
await t.go(`/attachments/${hostile.id}`);
await t.page.waitForTimeout(1500);
if ((await t.page.title()) === 'pwned') t.problems.push('hostile mail ran its script');
if (await t.page.locator('#preview_repository_entry_top img[onerror]').count()) t.problems.push('img onerror in the page');
const frame = t.page.frames().find(f => f.url().includes(`/more_preview/${hostile.id}/`));
if (frame && !(await frame.locator('pre', { hasText: '<b>bold?</b>' }).count())) t.problems.push('body tags not shown as text');
await t.page.mouse.move(0, 0);
await t.shot('hostile', 'A mail with <img onerror> in the subject and <script> in the body: both shown as text, nothing runs (the page title stays)', { full: false });
await t.page.request.delete(`${t.BASE}/attachments/${hostile.id}.json`, { headers: { 'X-Redmine-API-Key': await apiKey() } });
await t.done();

async function apiKey() {
  // written by test/e2e/seed.rb
  return fs.readFileSync(`${process.env.REDMINE_DIR}/tmp/e2e-manager-api-key`, 'utf8').trim();
}
