// Round 6 (port of curecodejp 6.1.3): LibreOffice converts in its bubblewrap sandbox. The
// ODT of the issue "E2E round 6" links a file of the server as its image
// (tmp/e2e-round6/server-secret.png, test/e2e/seed.rb): previewed as HTML and as PDF, the
// file is not in the preview. Administration > Information shows the sandbox check. Without
// a usable bwrap (made not executable for the refusal path, restored afterwards) Libre
// converts nothing: no fallback to LibreOffice outside the sandbox.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { execSync, execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const REDMINE = process.env.REDMINE_DIR;
const SECRET = fs.readFileSync(`${REDMINE}/tmp/e2e-round6/server-secret.png`);
const t = await e2e('libre_sandbox');
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
async function table(title, intro, rows) {
  await t.page.setContent(`<style>body{font:14px sans-serif;margin:24px}td,th{border:1px solid #ccc;padding:4px 8px;text-align:left}</style>` +
    `<h2>${esc(title)}</h2><p>${esc(intro)}</p><table><tr><th>${rows[0].map(esc).join('</th><th>')}</th></tr>` +
    rows.slice(1).map(r => `<tr><td>${r.map(esc).join('</td><td>')}</td></tr>`).join('') + '</table>');
}
const apiKey = () => ({ 'X-Redmine-API-Key': fs.readFileSync(`${REDMINE}/tmp/e2e-manager-api-key`, 'utf8').trim() });
async function attachments(subject) {
  const issue = (await (await t.page.request.get(`${t.BASE}/issues.json?project_id=e2e-project&subject=${encodeURIComponent(subject)}`, { headers: apiKey() })).json()).issues[0];
  const att = {};
  for (const a of (await (await t.page.request.get(`${t.BASE}/issues/${issue.id}.json?include=attachments`, { headers: apiKey() })).json()).issue.attachments) att[a.filename] = a.id;
  return att;
}
async function get(p) {
  const r = await t.page.request.get(t.BASE + p, { timeout: 180000 });
  return { status: r.status(), type: r.headers()['content-type'] || '', body: await r.body() };
}
async function setOdtFormat(format) {
  await t.go('/settings/plugin/redmine_more_previews');
  await t.sudo();
  await t.page.selectOption('select[name="settings[converter][libre][mime_types][odt][format]"]', format);
  await t.page.click('#settings form input[type=submit], form[action$="redmine_more_previews"] input[type=submit]');
  await t.settle();
  await t.sudo();
  const notice = await t.page.locator('#flash_notice').count();
  if (!notice) t.problems.push(`settings: saving odt -> ${format} showed no notice`);
}
const sandboxed = () => fs.readdirSync('/proc').filter(p => /^\d+$/.test(p)).some(p => {
  try { return fs.readFileSync(`/proc/${p}/cmdline`).includes('/profile/user_installation'); } catch { return false; }
});

await t.login('admin');
const att = { ...(await attachments('E2E round 6')), ...(await attachments('E2E previews')) };

// --- Administration > Information: the sandbox check
await t.go('/admin/info');
const row = t.page.locator('tr', { hasText: 'LibreOffice available in its sandbox (bubblewrap)' });
if (!(await row.count())) t.problems.push('admin info: no Libre sandbox check');
else if (!(await row.locator('.icon-ok').count())) t.problems.push('admin info: the Libre sandbox check failed on this host');
await row.scrollIntoViewIfNeeded().catch(() => {});
await t.shot('info-ok', 'Administration > Information: "LibreOffice available in its sandbox (bubblewrap)" is checked on this host (bwrap 0.9.0, unprivileged namespaces work)', { full: false });

// --- sandboxed conversions as the manager: docx -> pdf, odt -> html
await t.login('manager');
const rows = [['file', 'format', 'HTTP', 'type', 'checks']];
const docx = await get(`/attachments/more_preview/${att['sample.docx']}/index.pdf`);
rows.push(['sample.docx', 'pdf', docx.status, docx.type, docx.body.subarray(0, 5).toString()]);
if (docx.status !== 200 || !docx.body.subarray(0, 5).toString().startsWith('%PDF')) t.problems.push(`sample.docx pdf: HTTP ${docx.status}`);
const html = await get(`/attachments/more_preview/${att['external-image.odt']}/index.html`);
const htmlText = html.body.toString();
const htmlLeak = html.body.includes(SECRET) || htmlText.includes(SECRET.toString('base64'));
rows.push(['external-image.odt', 'html', html.status, html.type, `text ${htmlText.includes('E2E-SANDBOX') ? 'present' : 'MISSING'}, server file ${htmlLeak ? 'EMBEDDED' : 'not embedded'}`]);
if (html.status !== 200 || !htmlText.includes('E2E-SANDBOX')) t.problems.push(`external-image.odt html: HTTP ${html.status}`);
if (htmlLeak) t.problems.push('external-image.odt html: the server file is embedded');
// every file stored with the HTML preview (LibreOffice writes images next to it)
const cached = execSync(`find ${REDMINE}/tmp/more_previews/attachments/${att['external-image.odt']} -type f`).toString().trim().split('\n').filter(Boolean);
const leakFiles = cached.filter(f => fs.readFileSync(f).includes(SECRET));
rows.push(['external-image.odt', 'html, files in the cache', '', '', `${cached.length} file(s): ${cached.map(f => path.basename(f)).join(', ')}; with the server file: ${leakFiles.length}`]);
if (leakFiles.length) t.problems.push(`cache holds the server file: ${leakFiles.join(', ')}`);
await t.go(`/attachments/${att['external-image.odt']}`);
await t.page.waitForTimeout(2000);
await t.page.mouse.move(0, 0);
await t.shot('odt-html', 'external-image.odt previewed as HTML by LibreOffice in its sandbox: the text is there, the linked file of the server is not (a broken image at most)', { full: false });

// --- the same ODT as PDF (format changed on the settings page, back to html afterwards)
await t.login('admin');
await setOdtFormat('pdf');
await t.login('manager');
const pdf = await get(`/attachments/more_preview/${att['external-image.odt']}/index.pdf`);
let images = 'pdfimages not run';
if (pdf.status === 200) {
  const file = path.join(os.tmpdir(), `e2e-sandbox-${process.pid}.pdf`);
  fs.writeFileSync(file, pdf.body);
  const list = execFileSync('pdfimages', ['-list', file]).toString().trim().split('\n').slice(2);
  images = `${list.length} image(s) in the PDF${list.length ? ': ' + list.map(l => l.split(/\s+/).slice(3, 5).join('x')).join(', ') : ''}`;
  if (list.some(l => { const c = l.trim().split(/\s+/); return c[3] === '4' && c[4] === '4'; })) t.problems.push('external-image.odt pdf: the 4x4 server image is embedded');
  fs.rmSync(file, { force: true });
} else t.problems.push(`external-image.odt pdf: HTTP ${pdf.status}`);
rows.push(['external-image.odt', 'pdf', pdf.status, pdf.type, images]);
await t.go(`/attachments/${att['external-image.odt']}`);
await t.page.waitForTimeout(2000);
await table('LibreOffice in its sandbox, as manager', 'The ODT links tmp/e2e-round6/server-secret.png (a 4x4 PNG) of the server as its image. The sandbox mounts only the input file, the output directory, a profile and read-only system paths.', rows);
await t.shot('conversions', 'docx -> pdf and odt -> html/pdf convert in the sandbox; neither the HTML, nor the files stored with it, nor the PDF (pdfimages -list) hold the server file', { full: false });
if (sandboxed()) t.problems.push('a LibreOffice process of the sandbox is still running after the conversions');
await t.login('admin');
await setOdtFormat('html');

// --- no usable bwrap: Libre refuses, LibreOffice does not run outside the sandbox
const refusal = [['request', 'HTTP', 'answer']];
execSync('chmod a-x /usr/bin/bwrap');
try {
  await t.go('/admin/info');
  const failed = await t.page.locator('tr', { hasText: 'LibreOffice available in its sandbox (bubblewrap)' }).locator('.icon-error').count();
  if (!failed) t.problems.push('admin info: the Libre check did not fail without bwrap');
  await t.page.locator('tr', { hasText: 'LibreOffice available in its sandbox' }).scrollIntoViewIfNeeded().catch(() => {});
  await t.shot('info-refused', 'With /usr/bin/bwrap not executable the check fails: Libre will not convert', { full: false });
  // a document not converted before (the docx as html would be cached under another format)
  const r = await get(`/attachments/more_preview/${att['sample.xlsx']}/index.html?reload=1`);
  refusal.push(['sample.xlsx as html, reload (admin)', r.status, r.body.toString().slice(0, 60)]);
  if (r.status !== 404) t.problems.push(`without bwrap: sample.xlsx HTTP ${r.status}, expected 404`);
  const log = execSync(`tail -n 400 ${REDMINE}/log/production.log`).toString();
  if (!/LibreOffice sandbox unavailable/.test(log)) t.problems.push('without bwrap: no "LibreOffice sandbox unavailable" in the log');
  refusal.push(['production.log', '', /LibreOffice sandbox unavailable/.test(log) ? '"LibreOffice sandbox unavailable" logged' : 'nothing logged']);
  refusal.push(['soffice processes', '', sandboxed() || /soffice/.test(execSync('ps -eo args').toString().split('\n').filter(l => !/grep/.test(l)).join('\n')) ? 'RUNNING' : 'none started']);
  await t.go(`/attachments/${att['sample.xlsx']}`);
  await t.page.waitForTimeout(1500);
  await t.shot('page-refused', 'The page of sample.xlsx without the sandbox: the preview frame stays empty (404), nothing was converted', { full: false });
} finally {
  execSync('chmod a+x /usr/bin/bwrap');
}
await table('Libre without a usable sandbox, as admin', 'No fallback to LibreOffice outside the sandbox (upstream: "fail closed").', refusal);
await t.shot('refused', 'Without bwrap Libre answers 404 and logs why; no soffice runs', { full: false });
const back = await get(`/attachments/more_preview/${att['sample.xlsx']}/index.html?reload=1`);
if (back.status !== 200) t.problems.push(`bwrap restored: sample.xlsx HTTP ${back.status}`);
await t.done();
