// Round 7 (port of curecodejp 6.1.4), on files this scenario uploads to the issue
// "E2E previews" and removes again; settings through rails runner, restored from
// the seed at the end:
// - Vince: a vCard 3.0 with an inline PHOTO (TYPE=JPEG) and LOGO (TYPE=png), as
//   HTML (the MIME type from the fixed list: image/jpeg, not image/JPEG) and as
//   text (the humanize procs, fc40099);
// - Maggie: a PDF to png with Ghostscript absent gives no preview, never the PDF
//   under the png name (df0c1cf);
// - Libre: the HTML preview of a docx with an image, named "Offerte_Réunion 2026.docx",
//   and of a repository file "docs/会議録.docx": the image is shown (43a7eec,
//   6b15276, fa1fbca).
import { e2e } from '../../.codex/e2e/lib.mjs';
import { execSync } from 'node:child_process';
import fs from 'node:fs';

const REDMINE = process.env.REDMINE_DIR;
const t = await e2e('round7');
const env = { ...process.env, RAILS_ENV: process.env.RMP_SERVER_ENV || 'production' };
const rails = cmd => execSync(cmd, { cwd: REDMINE, env, encoding: 'utf8' }).trim();
const H = { 'X-Redmine-API-Key': fs.readFileSync(`${REDMINE}/tmp/e2e-manager-api-key`, 'utf8').trim() };
const fonts = { js: ['has been blocked by CORS policy'] }; // vcard: see converters.mjs
const setting = ruby => rails(`bundle exec rails runner "s = Setting.plugin_redmine_more_previews.to_h.deep_dup; ${ruby}; Setting.plugin_redmine_more_previews = s"`);

let gs = true;
try { execSync('command -v gs', { stdio: 'ignore', shell: '/bin/bash' }); } catch { gs = false; }

// --- files
const jpeg = execSync("convert -size 120x120 xc:'#c0392b' -fill white -pointsize 40 -gravity center -annotate 0 'JP' jpeg:-").toString('base64');
const png = execSync("convert -size 160x50 xc:'#27ae60' -fill white -pointsize 22 -gravity center -annotate 0 'LOGO' png:-").toString('base64');
// lines folded at 75 octets (RFC 6350 3.2); the reader cuts an unfolded long line
const fold = line => line.match(/.{1,74}/g).join('\r\n ');
const vcf = ['BEGIN:VCARD', 'VERSION:3.0', 'N:Peeters;Jan;;;', 'FN:Jan Peeters', 'ORG:Round 7 NV',
  'TEL;TYPE=WORK,VOICE:+32 9 765 43 21', fold(`PHOTO;ENCODING=b;TYPE=JPEG:${jpeg}`), fold(`LOGO;ENCODING=b;TYPE=png:${png}`),
  'END:VCARD', ''].join('\r\n');
const docx = fs.readFileSync('test/fixtures/files/sample_image.docx');

await t.anonymous();
const issue = (await (await t.page.request.get(`${t.BASE}/issues.json?project_id=e2e-project&subject=E2E%20previews`, { headers: H })).json()).issues[0];
const uploads = [];
for (const [filename, data, content_type] of [['round7-photo.vcf', Buffer.from(vcf), 'text/vcard'],
  ['Offerte_Réunion 2026.docx', docx, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document']]) {
  const up = await t.page.request.post(`${t.BASE}/uploads.json?filename=${encodeURIComponent(filename)}`, {
    headers: { ...H, 'Content-Type': 'application/octet-stream' }, data });
  uploads.push({ token: (await up.json()).upload.token, filename, content_type });
}
await t.page.request.put(`${t.BASE}/issues/${issue.id}.json`, { headers: { ...H, 'Content-Type': 'application/json' },
  data: { issue: { uploads } } });
const att = {};
for (const a of (await (await t.page.request.get(`${t.BASE}/issues/${issue.id}.json?include=attachments`, { headers: H })).json()).issue.attachments) att[a.filename] = a.id;
const sheet = async (name, title, rows) => {
  await t.page.setContent(`<h2>${title}</h2><pre style="white-space:pre-wrap">${rows.join('\n').replace(/</g, '&lt;')}</pre>`);
  await t.shot(name, title, { full: false });
};

// docx to html for Libre, maggie for pdf (Peek off), the repository file
setting(`s['converter']['libre']['mime_types']['docx'] = { 'active' => '1', 'format' => 'html' }; ` +
  `s['converter']['peek']['mime_types']['pdf']['active'] = '0'; ` +
  `s['converter']['maggie']['mime_types']['pdf'] = { 'active' => '1', 'format' => 'png' }`);
const repoDir = `${REDMINE}/tmp/e2e-repo`;
const git = args => execSync(`git -C ${repoDir} -c user.name=E2E -c user.email=e2e@example.net ${args}`, { encoding: 'utf8' });
fs.copyFileSync('test/fixtures/files/sample_image.docx', `${repoDir}/docs/会議録.docx`);
git('add docs'); git("commit -q -m 'round 7: a docx with a non-ASCII name'");
rails('bundle exec rails runner "Project.find_by!(identifier: \'e2e-project\').repositories.find_by!(identifier: \'samples\').fetch_changesets"');

await t.login('manager');

// --- Vince, HTML
const card = await (await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['round7-photo.vcf']}/index.html`)).text();
const srcs = [...card.matchAll(/<img[^>]* src="(data:[^;]*);base64/g)].map(m => m[1]);
if (!srcs.includes('data:image/jpeg')) t.problems.push(`vcard html: PHOTO TYPE=JPEG gave ${JSON.stringify(srcs)}, expected data:image/jpeg`);
if (!srcs.includes('data:image/png')) t.problems.push(`vcard html: LOGO TYPE=png gave ${JSON.stringify(srcs)}, expected data:image/png`);
await t.go(`/attachments/more_preview/${att['round7-photo.vcf']}/index.html`, { allow: fonts });
const vcardImgs = await t.page.locator('img.vcard').evaluateAll(imgs => imgs.map(i => `${i.alt}: ${i.naturalWidth}x${i.naturalHeight}`));
if (vcardImgs.length !== 2 || vcardImgs.some(s => s.endsWith(' 0x0'))) t.problems.push(`vcard html: images ${JSON.stringify(vcardImgs)}`);
await t.go(`/attachments/${att['round7-photo.vcf']}`, { allow: fonts });
await t.page.waitForTimeout(1500); await t.page.mouse.move(0, 0);
await t.shot('vcard-html', `round7-photo.vcf (vCard 3.0) as HTML: PHOTO TYPE=JPEG and LOGO TYPE=png shown, as ${srcs.join(' and ')}`, { full: false });

// --- Vince, text
setting(`s['converter']['vince']['mime_types']['vcf'] = { 'active' => '1', 'format' => 'txt' }`);
const txt = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['round7-photo.vcf']}/index.txt`);
const txtBody = await txt.text();
if (txt.status() !== 200 || !txtBody.includes('Jan Peeters') || !txtBody.includes('+32 9 765 43 21')) t.problems.push(`vcard txt: HTTP ${txt.status()}, ${JSON.stringify(txtBody.slice(0, 80))}`);
await t.go(`/attachments/${att['round7-photo.vcf']}`);
await t.page.waitForTimeout(1500); await t.page.mouse.move(0, 0);
await t.shot('vcard-txt', `round7-photo.vcf as text: HTTP ${txt.status()}, name and phone shown (PHOTO/LOGO are not in the text template)`, { full: false });

// --- Maggie, PDF without Ghostscript
const pdf = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['sample.pdf']}/index.png?reload=1`);
const pdfHead = (await pdf.body()).toString('latin1').slice(0, 5);
if (!gs && (pdf.status() !== 404 || pdfHead.startsWith('%PDF'))) t.problems.push(`maggie sample.pdf -> index.png without Ghostscript: HTTP ${pdf.status()}, starts with ${JSON.stringify(pdfHead)} (a PDF served as png)`);
await t.go(`/attachments/${att['sample.pdf']}`, { allow: { requests: [`404 image /attachments/more_preview/${att['sample.pdf']}/index.png`] } });
await t.page.waitForTimeout(1000); await t.page.mouse.move(0, 0);
await t.shot('maggie-pdf', `sample.pdf by Maggie to png, Ghostscript ${gs ? 'installed' : 'absent'}: index.png answers HTTP ${pdf.status()} (${pdfHead.startsWith('%PDF') ? 'the PDF under the png name' : 'no fake PNG'})`, { full: false });
await t.login('admin');
const reload = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['sample.pdf']}/index.png?reload=1`);
const reloadHead = (await reload.body()).toString('latin1').slice(0, 5);
if (!gs && reloadHead.startsWith('%PDF')) t.problems.push('maggie sample.pdf: admin reload served the PDF as png');
// with Ghostscript the admin's reload converts; a failure remembered from before
// (failure_ttl) may still answer the manager with 404
if (gs && !reloadHead.startsWith('\x89PNG')) t.problems.push(`maggie sample.pdf with Ghostscript, admin reload: ${JSON.stringify(reloadHead)}`);
await sheet('maggie-results', 'Maggie, sample.pdf to png', [`Ghostscript: ${gs ? 'installed' : 'absent'}`,
  `manager GET index.png?reload=1 (reload is admin only): HTTP ${pdf.status()}, first bytes ${JSON.stringify(pdfHead)}`,
  `admin   GET index.png?reload=1: HTTP ${reload.status()}, first bytes ${JSON.stringify(reloadHead)}`]);
await t.login('manager');

// --- Libre, HTML with an image, accented attachment name
const libreRows = [];
async function libre(label, previewUrl, pageUrl, shotName) {
  const r = await t.page.request.get(t.BASE + previewUrl);
  const body = await r.text();
  const links = [...body.matchAll(/<img[^>]* src="([^"]+)"/gi)].map(m => m[1]);
  await t.go(previewUrl);
  const imgs = await t.page.locator('img').evaluateAll(list => list.map(i => ({ src: i.getAttribute('src'), size: `${i.naturalWidth}x${i.naturalHeight}` })));
  libreRows.push(`${label}: HTTP ${r.status()}, links ${JSON.stringify(links)}, loaded ${JSON.stringify(imgs.map(i => i.size))}`);
  if (r.status() !== 200 || !body.includes('LIBRE-IMAGE-LINK-TEST')) t.problems.push(`${label}: HTTP ${r.status()}, no document text`);
  if (imgs.length !== 1 || imgs[0].size === '0x0') t.problems.push(`${label}: image not shown ${JSON.stringify(imgs)}`);
  if (links.some(l => /%C3%83|%C3%A4%C2/.test(l))) t.problems.push(`${label}: link encoded twice ${links}`);
  await t.go(pageUrl);
  await t.page.waitForTimeout(2000); await t.page.mouse.move(0, 0);
  await t.shot(shotName, `${label} as HTML by LibreOffice (sandbox): the image is shown; link ${links.join(', ')}`, { full: false });
}
await libre('Offerte_Réunion 2026.docx (attachment)', `/attachments/more_preview/${att['Offerte_Réunion 2026.docx']}/index.html`,
  `/attachments/${att['Offerte_Réunion 2026.docx']}`, 'libre-attachment');
const R = '/projects/e2e-project/repository/samples';
await libre('docs/会議録.docx (repository)', `${R}/preview/docs/${encodeURIComponent('会議録.docx')}@/index.html`,
  `${R}/entry/docs/${encodeURIComponent('会議録.docx')}`, 'libre-repository');
await sheet('libre-results', 'Libre HTML previews with non-ASCII names', libreRows);

// --- the same as reporter (no plugin permissions; the plugin's permission is public)
await t.login('reporter');
const rep = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['Offerte_Réunion 2026.docx']}/index.html`);
if (rep.status() !== 200) t.problems.push(`reporter: Libre preview HTTP ${rep.status()}`);
await t.go(`/attachments/${att['Offerte_Réunion 2026.docx']}`);
await t.page.waitForTimeout(2000); await t.page.mouse.move(0, 0);
await t.shot('reporter-libre', `reporter (core Reporter role): the same preview, HTTP ${rep.status()}`, { full: false });

// clean up: the uploads, the repository file, the seed's settings
for (const name of ['round7-photo.vcf', 'Offerte_Réunion 2026.docx']) await t.page.request.delete(`${t.BASE}/attachments/${att[name]}.json`, { headers: H });
git('rm -q docs/会議録.docx'); git("commit -q -m 'round 7: removed again'");
rails(`bundle exec rails runner ${process.cwd()}/test/e2e/seed.rb`);
await t.done();
