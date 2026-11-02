// Round 8 (port of curecodejp 6.1.5), on files this scenario uploads to the issue
// "E2E previews" and removes again; settings through rails runner, restored at the end:
// - Vince (GHSA-hm82-jvvw-hmg4, 6b44d3a): a vCard as HTML and as text, no stray '%>'
//   after the logo; a vCard over 20 MiB is answered with 413 before forking, and
//   the server answers the next request (same process);
// - Cliff (5ac6319): an email with an attachment without extension (Makefile) and
//   one with an extension of other characters (source.c++), as an attachment and
//   in the repository: the email is previewed, Makefile listed as text, the
//   others linked by the first conversion and served;
// - Cliff (d6a2029): the attachment and repository pages of an email read the
//   headers from the cache: the stored headers.html is replaced by a probe, the
//   next view shows the probe (the old code converted the email again and showed
//   the real headers); the time of five page views is listed.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { execSync } from 'node:child_process';
import fs from 'node:fs';

const REDMINE = process.env.REDMINE_DIR;
const t = await e2e('round8');
const env = { ...process.env, RAILS_ENV: process.env.RMP_SERVER_ENV || 'production' };
const rails = cmd => execSync(cmd, { cwd: REDMINE, env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }).trim();
const runner = ruby => rails(`bundle exec rails runner '${ruby.replace(/'/g, `'\\''`)}'`);
const H = { 'X-Redmine-API-Key': fs.readFileSync(`${REDMINE}/tmp/e2e-manager-api-key`, 'utf8').trim() };
const fonts = { js: ['has been blocked by CORS policy'] }; // vcard: see converters.mjs
const pid = () => fs.readFileSync(`${REDMINE}/tmp/pids/e2e-${process.env.RMP_PORT || 3000}.pid`, 'utf8').trim();
const rows = [];
const note = line => rows.push(line);

// --- files
const vcf = ['BEGIN:VCARD', 'VERSION:4.0', 'FN:Round Eight', 'N:Eight;Round;;;', 'ORG:Round 8 NV',
  'TEL;TYPE=work:+32 9 888 88 88', 'END:VCARD', ''].join('\r\n');
// 20 MiB and one card more: many small cards, as a real export would be
const card = n => `BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Bulk ${n}\r\nNOTE:${'x'.repeat(200)}\r\nEND:VCARD\r\n`;
const bulkParts = []; let bulkSize = 0;
for (let n = 0; bulkSize <= 20 * 1024 * 1024; n++) { const c = card(n); bulkParts.push(c); bulkSize += c.length; }
const bulk = Buffer.from(bulkParts.join(''));
const b64 = s => Buffer.from(s).toString('base64');
const part = (name, type, body) => ['--BOUNDARY', `Content-Type: ${type}; name="${name}"`, 'Content-Transfer-Encoding: base64',
  `Content-Disposition: attachment; filename="${name}"`, '', b64(body), ''].join('\r\n');
const eml = ['From: Writer <writer@example.test>', 'To: Reader <reader@example.test>', 'Subject: Round 8 attachments',
  'Date: Mon, 02 Nov 2026 10:00:00 +0100', 'MIME-Version: 1.0', 'Content-Type: multipart/mixed; boundary="BOUNDARY"', '',
  '--BOUNDARY', 'Content-Type: text/plain; charset=UTF-8', '', 'ROUND8-MAIL-BODY', '',
  part('Makefile', 'application/octet-stream', 'all: test\n'), part('notes.txt', 'text/plain', 'ROUND8-NOTE\n'),
  part('source.c++', 'text/plain', 'int main() { return 0; }\n'), part('backup.txt~', 'text/plain', 'ROUND8-BACKUP\n'),
  '--BOUNDARY--', ''].join('\r\n');

await t.anonymous();
const issue = (await (await t.page.request.get(`${t.BASE}/issues.json?project_id=e2e-project&subject=E2E%20previews`, { headers: H })).json()).issues[0];
const maxSize = runner('puts Setting.attachment_max_size');
runner('Setting.attachment_max_size = 30720');
const uploads = [];
for (const [filename, data, content_type] of [['round8.vcf', Buffer.from(vcf), 'text/vcard'], ['round8-bulk.vcf', bulk, 'text/vcard'],
  ['round8.eml', Buffer.from(eml), 'message/rfc822']]) {
  const up = await t.page.request.post(`${t.BASE}/uploads.json?filename=${encodeURIComponent(filename)}`, {
    headers: { ...H, 'Content-Type': 'application/octet-stream' }, data });
  if (up.status() !== 201) t.problems.push(`upload ${filename}: HTTP ${up.status()}`);
  uploads.push({ token: (await up.json()).upload.token, filename, content_type });
}
await t.page.request.put(`${t.BASE}/issues/${issue.id}.json`, { headers: { ...H, 'Content-Type': 'application/json' },
  data: { issue: { uploads } } });
const att = {};
for (const a of (await (await t.page.request.get(`${t.BASE}/issues/${issue.id}.json?include=attachments`, { headers: H })).json()).issue.attachments) att[a.filename] = a.id;

const repoDir = `${REDMINE}/tmp/e2e-repo`;
const git = args => execSync(`git -C ${repoDir} -c user.name=E2E -c user.email=e2e@example.net ${args}`, { encoding: 'utf8' });
fs.writeFileSync(`${repoDir}/round8.eml`, eml);
git('add round8.eml'); git("commit -q -m 'round 8: an email with attachments'");
runner(`Project.find_by!(identifier: "e2e-project").repositories.find_by!(identifier: "samples").fetch_changesets`);

const sheet = async (name, title, lines) => {
  await t.page.setContent(`<h2>${title}</h2><pre style="white-space:pre-wrap">${lines.join('\n').replace(/</g, '&lt;')}</pre>`);
  await t.shot(name, title, { full: false });
};

await t.login('manager');

// --- Vince, HTML and text
const html = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['round8.vcf']}/index.html?reload=1`);
const htmlBody = await html.text();
note(`vCard HTML: HTTP ${html.status()}, 'Round Eight' ${htmlBody.includes('Round Eight')}, '%>' ${htmlBody.includes('%>')}, logo tag ${JSON.stringify((htmlBody.match(/<img[^>]*class="logo"[^>]*>( %>)?/) || [''])[0].slice(-30))}`);
if (html.status() !== 200 || !htmlBody.includes('Round Eight') || htmlBody.includes('%>')) t.problems.push(`vcard html: HTTP ${html.status()}, '%>' ${htmlBody.includes('%>')}`);
await t.go(`/attachments/${att['round8.vcf']}`, { allow: fonts });
await t.page.waitForTimeout(1500); await t.page.mouse.move(0, 0);
const frameText = await t.page.frameLocator('#preview_frame, object, iframe').first().locator('body').innerText().catch(() => '');
if (frameText.includes('%>')) t.problems.push('vcard html: %> shown on the page');
await t.shot('vcard-html', `round8.vcf as HTML (Vince in a child process): card shown, no '%>' after the logo (HTTP ${html.status()})`, { full: false });

runner(`s = Setting.plugin_redmine_more_previews.to_h.deep_dup; s["converter"]["vince"]["mime_types"]["vcf"] = { "active" => "1", "format" => "txt" }; Setting.plugin_redmine_more_previews = s`);
const txt = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['round8.vcf']}/index.txt`);
const txtBody = await txt.text();
note(`vCard text: HTTP ${txt.status()}, 'Round Eight' ${txtBody.includes('Round Eight')}, '+32 9 888 88 88' ${txtBody.includes('+32 9 888 88 88')}, '%>' ${txtBody.includes('%>')}`);
if (txt.status() !== 200 || !txtBody.includes('Round Eight') || !txtBody.includes('+32 9 888 88 88') || txtBody.includes('%>')) t.problems.push(`vcard txt: HTTP ${txt.status()}, ${JSON.stringify(txtBody.slice(0, 80))}`);
await t.go(`/attachments/${att['round8.vcf']}`);
await t.page.waitForTimeout(1500); await t.page.mouse.move(0, 0);
await t.shot('vcard-txt', `round8.vcf as text: name and phone shown, no '%>' (HTTP ${txt.status()})`, { full: false });
runner(`s = Setting.plugin_redmine_more_previews.to_h.deep_dup; s["converter"]["vince"]["mime_types"]["vcf"] = { "active" => "1", "format" => "html" }; Setting.plugin_redmine_more_previews = s`);

// --- Vince, a vCard over 20 MiB
const before = pid();
const big = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['round8-bulk.vcf']}/index.html`);
const bigBody = await big.text();
const after = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['round8.vcf']}/index.html`);
const log = execSync(`grep -a "round8-bulk\\|${att['round8-bulk.vcf']}" ${REDMINE}/log/production.log | grep -a "larger than 20 MiB" | tail -1`, { encoding: 'utf8', shell: '/bin/bash' }).trim();
note(`vCard of ${bulk.length} bytes: HTTP ${big.status()}, body ${JSON.stringify(bigBody.slice(0, 60))}; server pid ${before} before, ${pid()} after; next preview HTTP ${after.status()}`);
note(`log: ${log.replace(/^.*?(Preview for)/, '$1').replace(/\/[^ ]*\//, '.../')}`);
if (big.status() !== 413) t.problems.push(`vcard over 20 MiB: HTTP ${big.status()}, expected 413`);
if (pid() !== before || after.status() !== 200) t.problems.push(`after the large vCard: pid ${before} -> ${pid()}, next preview HTTP ${after.status()}`);
if (!log) t.problems.push('vcard over 20 MiB: no "larger than 20 MiB" in the log');
await t.go(`/attachments/${att['round8-bulk.vcf']}`, { allow: { requests: [`413 `] } });
await t.page.waitForTimeout(1500); await t.page.mouse.move(0, 0);
await t.shot('vcard-too-large', `round8-bulk.vcf, ${(bulk.length / 1048576).toFixed(1)} MiB: refused with 413 before forking; the server (pid ${before}) still answers. The page shows no preview and no reason (a browser shows nothing of a 413 in the frame; only Cliff has a warning above it)`, { full: false });

// --- Cliff, an email with attachments without and with unusual extensions
async function cliffList(label, frameUrl, listUrl, pageUrl, assetBase, shotName) {
  const frame = await t.page.request.get(t.BASE + frameUrl);
  const frameBody = await frame.text();
  const list = await t.page.request.get(t.BASE + listUrl);
  const listBody = await list.text();
  const links = [...listBody.matchAll(/<a [^>]*href="([^"]+)"[^>]*>([^<]+)<\/a>/g)].map(m => [m[2], m[1].replace(/&amp;/g, '&')]);
  note(`${label}: preview HTTP ${frame.status()} body ${frameBody.includes('ROUND8-MAIL-BODY')}; list HTTP ${list.status()}, 'Makefile' listed ${listBody.includes('Makefile')}, linked ${JSON.stringify(links.map(l => l[0]))}`);
  if (frame.status() !== 200 || !frameBody.includes('ROUND8-MAIL-BODY')) t.problems.push(`${label}: email not previewed (HTTP ${frame.status()})`);
  if (!listBody.includes('Makefile') || links.some(l => l[0] === 'Makefile')) t.problems.push(`${label}: Makefile not listed as text`);
  for (const name of ['notes.txt', 'source.c++', 'backup.txt~']) {
    const link = links.find(l => l[0] === name);
    if (!link) { t.problems.push(`${label}: no link for ${name}`); continue; }
    const r = await t.page.request.get(t.BASE + link[1]);
    note(`  ${name}: ${link[1]} -> HTTP ${r.status()}`);
    if (r.status() !== 200) t.problems.push(`${label}: ${name} HTTP ${r.status()}`);
  }
  const direct = await t.page.request.get(`${t.BASE}${assetBase}source.c++`);
  note(`  ${assetBase}source.c++ -> HTTP ${direct.status()} ${JSON.stringify((await direct.text()).slice(0, 24))}`);
  if (direct.status() !== 200) t.problems.push(`${label}: source.c++ HTTP ${direct.status()}`);
  await t.go(pageUrl);
  await t.page.waitForTimeout(2000); await t.page.mouse.move(0, 0);
  await t.shot(shotName, `${label}: previewed; Makefile listed without a link, notes.txt, source.c++, backup.txt~ linked`, { full: false });
}
const R = '/projects/e2e-project/repository/samples';
await cliffList('round8.eml (attachment)', `/attachments/more_preview/${att['round8.eml']}/index.html?reload=1`,
  `/attachments/more_preview/${att['round8.eml']}/attachments.html`, `/attachments/${att['round8.eml']}`,
  `/attachments/more_preview/${att['round8.eml']}/`, 'cliff-attachment');
await cliffList('round8.eml (repository)', `${R}/preview/round8.eml@/index.html`, `${R}/preview/round8.eml@/attachments.html`,
  `${R}/entry/round8.eml`, `${R}/preview/round8.eml@/`, 'cliff-repository');

// --- Cliff, the headers read from the cache
const paths = JSON.parse(runner(`a = Attachment.find(${att['round8.eml']}); r = Project.find_by!(identifier: "e2e-project").repositories.find_by!(identifier: "samples"); ` +
  `puts({ "attachment" => a.preview_assetpath(asset: "headers.html"), "repository" => r.preview_assetpath("round8.eml", nil, asset: "headers.html") }.to_json)`));
async function cached(label, pageUrl, path) {
  const times = [];
  for (let i = 0; i < 5; i++) {
    const t0 = Date.now();
    // a browser's Accept: */* alone gets core's page of the file, not the preview
    const r = await t.page.request.get(t.BASE + pageUrl, { headers: { Accept: 'text/html' } });
    await r.text();
    times.push(Date.now() - t0);
  }
  const stored = fs.existsSync(path);
  const original = stored ? fs.readFileSync(path) : null;
  if (stored) fs.writeFileSync(path, '<p>CACHED-HEADERS-PROBE</p>');
  const r = await t.page.request.get(t.BASE + pageUrl, { headers: { Accept: 'text/html' } });
  const probe = (await r.text()).includes('CACHED-HEADERS-PROBE');
  if (stored) fs.writeFileSync(path, original);
  note(`${label}: headers.html stored ${stored}; the page shows the stored file (probe) ${probe}; five views ${times.join(', ')} ms`);
  if (!stored || !probe) t.problems.push(`${label}: headers not read from the cache (stored ${stored}, probe ${probe})`);
  await t.go(pageUrl);
  await t.page.waitForTimeout(1500); await t.page.mouse.move(0, 0);
  await t.shot(`${label.split(' ')[0]}-headers`, `${label}, second view: the headers above the email read from the cache`, { full: false });
}
await cached('attachment page of round8.eml', `/attachments/${att['round8.eml']}`, paths.attachment);
await cached('repository page of round8.eml', `${R}/entry/round8.eml`, paths.repository);

// --- the same email as reporter (no plugin permissions; the plugin's permission is public)
await t.login('reporter');
await t.go(`/attachments/${att['round8.eml']}`);
await t.page.waitForTimeout(1500); await t.page.mouse.move(0, 0);
const repHeaders = await t.page.locator('#preview_repository_entry_top table.white').count();
note(`reporter, attachment page of round8.eml: headers box ${repHeaders}`);
if (repHeaders !== 1) t.problems.push(`reporter: headers box ${repHeaders}`);
await t.shot('reporter-cliff', 'reporter (core Reporter role): the email with its headers from the cache', { full: false });

await sheet('results', 'Round 8 results', rows);

// clean up: the uploads, the repository file, the settings
await t.login('manager');
for (const name of ['round8.vcf', 'round8-bulk.vcf', 'round8.eml']) await t.page.request.delete(`${t.BASE}/attachments/${att[name]}.json`, { headers: H });
git('rm -q round8.eml'); git("commit -q -m 'round 8: removed again'");
runner(`Setting.attachment_max_size = ${Number(maxSize)}`);
rails(`bundle exec rails runner ${process.cwd()}/test/e2e/seed.rb`);
await t.done();
