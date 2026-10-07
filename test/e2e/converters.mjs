// Every converter on an attachment, as the manager: the preview page of each
// sample file of the issue "E2E previews" (test/e2e/seed.rb), with the
// conversion checked through its own URL (status, type, content).
import { e2e } from '../../.codex/e2e/lib.mjs';
import fs from 'node:fs';

const t = await e2e('converters');
await t.login('manager');

const issues = await (await t.page.request.get(`${t.BASE}/issues.json?project_id=e2e-project&subject=E2E%20previews`, { headers: e2eApiKey() })).json();
const issue = issues.issues[0];
const att = {};
for (const a of (await (await t.page.request.get(`${t.BASE}/issues/${issue.id}.json?include=attachments`, { headers: e2eApiKey() })).json()).issue.attachments) att[a.filename] = a.id;

// The vcard preview links Redmine's application.css; in the sandboxed preview
// (opaque origin) its web fonts are refused by CORS, the text falls back to a system font.
const fonts = { js: ['has been blocked by CORS policy'] };

const cases = [
  ['sample.docx', 'pdf', 'application/pdf', '%PDF', 'Libre: docx converted to PDF by LibreOffice (headless Chromium shows no PDF viewer; the PDF itself is checked through its URL)'],
  ['sample.odt', 'html', 'text/html', 'Office sample', 'Libre: odt converted to HTML by LibreOffice'],
  ['sample.xlsx', 'html', 'text/html', 'apple', 'Libre: xlsx converted to HTML (the sheet as a table)'],
  ['sample.csv', 'png', 'image/png', null, 'Libre: csv rendered as a PNG image'],
  ['sample.eml', 'html', 'text/html', 'this is the body of the sample mail', 'Cliff: mail headers in a box above the body, "Unsafe reload" link'],
  ['sample.vcf', 'html', 'text/html', 'John Doe', 'Vince: business card from a vcf', fonts],
  ['sample.md', 'html', 'text/html', '<em>emphasis</em>', 'Mark: markdown converted to HTML by pandoc'],
  ['sample.textile', null, null, null, 'Mark: textile rendered inline in the page (was HTTP 500 before this branch)'],
  ['sample.html', 'html', 'text/html', 'Passed through as HTML', 'Pass: html shown as is, sandboxed'],
  ['sample.txt', 'txt', 'text/plain', 'Plain text sample', 'Teddie: text file'],
  ['sample.pdf', 'pdf', 'application/pdf', '%PDF', 'Peek: the PDF itself (no viewer in headless Chromium; checked through its URL)'],
  ['sample.png', 'jpg', 'image/jpeg', null, 'Maggie: png converted to jpg by ImageMagick'],
  ['sample.zip', 'html', 'text/html', 'hello.txt', 'Zippy: zip content table with folders'],
  ['sample.tar', null, null, null, 'Zippy: tar content table rendered inline'],
  ['sample.tgz', 'html', 'text/html', 'hello.txt', 'Zippy: tgz content table'],
];

for (const [name, format, type, needle, caption, allow] of cases) {
  const id = att[name];
  await t.go(`/attachments/${id}`, { allow });
  if (!(await t.page.locator('#preview_repository_entry_top').count())) t.problems.push(`${name}: the plugin's preview page is not shown`);
  if (format) {
    const res = await t.page.request.get(`${t.BASE}/attachments/more_preview/${id}/index.${format}`);
    const body = await res.body();
    if (res.status() !== 200) t.problems.push(`${name}: preview HTTP ${res.status()}`);
    if (!res.headers()['content-type'].startsWith(type)) t.problems.push(`${name}: preview type ${res.headers()['content-type']}`);
    if (needle && !body.toString('latin1').includes(needle)) t.problems.push(`${name}: preview lacks "${needle}"`);
    const csp = res.headers()['content-security-policy'] || '';
    if (type === 'application/pdf' ? csp : !csp.startsWith('sandbox')) t.problems.push(`${name}: unexpected CSP "${csp}"`);
  } else {
    const inline = t.page.locator('#preview_repository_entry_top + div');
    const text = (await inline.count()) ? await inline.innerText() : '';
    if (!/Textile sample|hello\.txt/.test(text)) t.problems.push(`${name}: inline preview is empty`);
  }
  await t.page.waitForTimeout(1500); // the embedded document
  await t.page.mouse.move(0, 0); // no tooltip of the embedded document in the picture
  t.check(name, allow);
  await t.shot(name.replace('.', '-'), caption, { full: false });
}

// navigation between the attachments of the issue
await t.go(`/attachments/${att['sample.md']}`);
await t.page.click('.pagination.filepreview a:has-text("Next »")');
await t.settle();
if (!t.page.url().includes(`/attachments/${att['sample.odt']}`)) t.problems.push(`next: landed on ${t.page.url()}`);
await t.page.waitForTimeout(1500);
await t.shot('navigation-next', '"Next »" leads from sample.md to the next attachment of the issue (sample.odt)', { full: false });

// Update (reload) regenerates the preview
await t.page.click('#content a.icon-reload');
await t.settle();
if (!t.page.url().includes('reload=1')) t.problems.push(`reload: ${t.page.url()}`);
await t.page.waitForTimeout(1500);
await t.shot('reload', 'The "Update" link (SVG reload icon) reconverts the file', { full: false });

// the file icons the plugin adds to attachment lists
await t.go(`/issues/${issue.id}`);
const iconCss = await t.page.evaluate(() => document.head.innerHTML.includes('.icon-file.'));
if (!iconCss) t.problems.push('icon css hook missing');
await t.shot('issue-attachments', 'The issue with its sample attachments; the plugin adds file-type icons through a CSS hook');
await t.done();

// lookups through the manager's API key (test/e2e/seed.rb): a plugin may restrict issue data for a session
function e2eApiKey() {
  return { 'X-Redmine-API-Key': fs.readFileSync(`${process.env.REDMINE_DIR}/tmp/e2e-manager-api-key`, 'utf8').trim() };
}
