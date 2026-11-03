// Round 9 (port of curecodejp 6.1.6), on files this scenario uploads to the issue
// "E2E previews" and removes again; settings through rails runner, restored at the end:
// - inline previews (5fb219a, dc493bc): a textile converted to more than 256 KiB of
//   html is not stored, sanitized or embedded: the page shows the size notice and
//   the server answers the next request at once (same process); a small one is
//   shown as before;
// - Cliff fragments (ebe0641): an email whose header fields convert to more than
//   256 KiB shows the notice in place of the fields box, the headers and the body
//   stay; the fragment requested directly answers 413;
// - bed742c: a fields.html stored before the limit (same file and mtime, so the
//   same ETag) answers a conditional request with 413, not 304; a regular one 304;
// - 6ce4793: an email beyond Cliff's size limit keeps the attachment page, with the
//   reason, a download link and the preview frame (the frame answers 413); the same
//   without the cache. Repository entries for the fragment too.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { execSync } from 'node:child_process';
import fs from 'node:fs';

const REDMINE = process.env.REDMINE_DIR;
const t = await e2e('round9');
const env = { ...process.env, RAILS_ENV: process.env.RMP_SERVER_ENV || 'production' };
const rails = cmd => execSync(cmd, { cwd: REDMINE, env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }).trim();
const runner = ruby => rails(`bundle exec rails runner '${ruby.replace(/'/g, `'\\''`)}'`);
const H = { 'X-Redmine-API-Key': fs.readFileSync(`${REDMINE}/tmp/e2e-manager-api-key`, 'utf8').trim() };
const pid = () => fs.readFileSync(`${REDMINE}/tmp/pids/e2e-${process.env.RMP_PORT || 3000}.pid`, 'utf8').trim();
const NOTICE = 'The inline preview exceeds the size limit. Download the file to view it.';
const rows = [];
const note = line => rows.push(line);
const count = (s, sub) => s.split(sub).length - 1;

// --- files
const small = 'h2. Round nine\n\nA *small* inline preview, ROUND9-SMALL.\n';
// about 330 KiB of html: each paragraph a <p> with an <em>
const big = 'h2. Round nine big\n\n' + Array.from({ length: 6000 }, (_, i) => `Paragraph ${i} with _emphasis_ ROUND9-BIG.\n`).join('\n');
const headers = (subject, extra = '') => ['From: Writer <writer@example.test>', 'To: Reader <reader@example.test>', `Subject: ${subject}`,
  'Date: Tue, 03 Nov 2026 10:00:00 +0100', 'MIME-Version: 1.0', 'Content-Type: text/plain; charset=UTF-8', extra].filter(Boolean).join('\r\n');
// 950 header fields of about 300 bytes: fields.html over 256 KiB, the email under Cliff's 1 MiB
// (Mail keeps 1,000 header fields at most)
const pad = Array.from({ length: 950 }, (_, i) => `X-Pad-${i}: ${'p'.repeat(290)}`).join('\r\n');
const fieldsEml = headers('ROUND9-FIELDS-SUBJECT', pad) + '\r\n\r\nROUND9-FIELDS-BODY\r\n';
const plainEml = headers('ROUND9-PLAIN-SUBJECT') + '\r\n\r\nROUND9-PLAIN-BODY\r\n';
// over Cliff's max_size of 1 MiB (seed)
const hugeEml = headers('ROUND9-HUGE-SUBJECT') + '\r\n\r\n' + ('x'.repeat(76) + '\r\n').repeat(16000);

await t.anonymous();
const issue = (await (await t.page.request.get(`${t.BASE}/issues.json?project_id=e2e-project&subject=E2E%20previews`, { headers: H })).json()).issues[0];
const uploads = [];
for (const [filename, data, content_type] of [['round9-small.textile', small, 'text/x-web-textile'], ['round9-big.textile', big, 'text/x-web-textile'],
  ['round9-fields.eml', fieldsEml, 'message/rfc822'], ['round9-plain.eml', plainEml, 'message/rfc822'], ['round9-huge.eml', hugeEml, 'message/rfc822']]) {
  const up = await t.page.request.post(`${t.BASE}/uploads.json?filename=${encodeURIComponent(filename)}`, {
    headers: { ...H, 'Content-Type': 'application/octet-stream' }, data: Buffer.from(data) });
  if (up.status() !== 201) t.problems.push(`upload ${filename}: HTTP ${up.status()}`);
  uploads.push({ token: (await up.json()).upload.token, filename, content_type });
}
await t.page.request.put(`${t.BASE}/issues/${issue.id}.json`, { headers: { ...H, 'Content-Type': 'application/json' },
  data: { issue: { uploads } } });
const att = {};
for (const a of (await (await t.page.request.get(`${t.BASE}/issues/${issue.id}.json?include=attachments`, { headers: H })).json()).issue.attachments) att[a.filename] = a.id;

const repoDir = `${REDMINE}/tmp/e2e-repo`;
const git = args => execSync(`git -C ${repoDir} -c user.name=E2E -c user.email=e2e@example.net ${args}`, { encoding: 'utf8' });
fs.writeFileSync(`${repoDir}/round9-fields.eml`, fieldsEml);
fs.writeFileSync(`${repoDir}/round9-plain.eml`, plainEml);
git('add round9-fields.eml round9-plain.eml'); git("commit -q -m 'round 9: emails'");
runner(`Project.find_by!(identifier: "e2e-project").repositories.find_by!(identifier: "samples").fetch_changesets`);
const R = '/projects/e2e-project/repository/samples';

const sheet = async (name, title, lines) => {
  await t.page.setContent(`<h2>${title}</h2><pre style="white-space:pre-wrap">${lines.join('\n').replace(/</g, '&lt;')}</pre>`);
  await t.shot(name, title, { full: false });
};
const page = async url => {
  const t0 = Date.now();
  const r = await t.page.request.get(t.BASE + url, { headers: { Accept: 'text/html' } });
  const body = await r.text();
  return { status: r.status(), body, ms: Date.now() - t0 };
};

await t.login('manager');

// --- inline previews
const before = pid();
const s1 = await page(`/attachments/${att['round9-small.textile']}`);
note(`round9-small.textile: HTTP ${s1.status}, shown ${s1.body.includes('ROUND9-SMALL')} (<strong> ${s1.body.includes('<strong>small</strong>')}), notice ${s1.body.includes(NOTICE)}`);
if (s1.status !== 200 || !s1.body.includes('ROUND9-SMALL') || s1.body.includes(NOTICE)) t.problems.push('small inline preview changed');
const b1 = await page(`/attachments/${att['round9-big.textile']}`);
const b2 = await page(`/attachments/${att['round9-big.textile']}`);
const next = await page(`/attachments/${att['round9-small.textile']}`);
const stored = runner(`a = Attachment.find(${att['round9-big.textile']}); puts File.exist?(a.preview_filepath(format: "inline"))`);
note(`round9-big.textile (${big.length} bytes of textile): first view HTTP ${b1.status} in ${b1.ms} ms, notice ${count(b1.body, NOTICE)}, html embedded ${b1.body.includes('ROUND9-BIG')}; second view HTTP ${b2.status} in ${b2.ms} ms, notice ${count(b2.body, NOTICE)}; preview stored ${stored}`);
note(`server pid ${before} before, ${pid()} after; next page HTTP ${next.status} in ${next.ms} ms`);
if (b1.status !== 200 || count(b1.body, NOTICE) !== 1 || b1.body.includes('ROUND9-BIG') || b2.status !== 200 || count(b2.body, NOTICE) !== 1) t.problems.push('big inline preview: no notice, or embedded');
if (stored !== 'false') t.problems.push(`big inline preview stored: ${stored}`);
if (pid() !== before || next.status !== 200) t.problems.push('server not responsive after the big inline preview');
await t.go(`/attachments/${att['round9-small.textile']}`);
await t.shot('inline-small', 'round9-small.textile, inline: shown in the page as before', { full: false });
await t.go(`/attachments/${att['round9-big.textile']}`);
await t.shot('inline-big', `round9-big.textile, inline: html over 256 KiB, the size notice in the page instead of the preview; page in ${b1.ms} ms`, { full: false });

// --- Cliff, an oversized fragment (fields.html)
async function fragments(label, pageUrl, fieldsUrl, headersUrl, shotName) {
  const p = await page(pageUrl);
  const f = await t.page.request.get(t.BASE + fieldsUrl);
  const h = await t.page.request.get(t.BASE + headersUrl);
  note(`${label}: page HTTP ${p.status}, notice ${count(p.body, NOTICE)}, subject ${p.body.includes('ROUND9-FIELDS-SUBJECT')}, fields embedded ${p.body.includes('X-Pad-949')}; fields.html HTTP ${f.status()}, headers.html HTTP ${h.status()}`);
  if (p.status !== 200 || count(p.body, NOTICE) !== 1 || !p.body.includes('ROUND9-FIELDS-SUBJECT') || p.body.includes('X-Pad-949')) t.problems.push(`${label}: page`);
  if (f.status() !== 413) t.problems.push(`${label}: fields.html HTTP ${f.status()}, expected 413`);
  if (h.status() !== 200) t.problems.push(`${label}: headers.html HTTP ${h.status()}`);
  await t.go(pageUrl);
  await t.page.waitForTimeout(1500); await t.page.mouse.move(0, 0);
  // the preview is an <object> (embedding 0): its document is one of the page's frames
  const frame = (await Promise.all(t.page.frames().map(f => f.content().catch(() => '')))).slice(1).join('');
  note(`  preview frame shows the body ${frame.includes('ROUND9-FIELDS-BODY')}`);
  if (!frame.includes('ROUND9-FIELDS-BODY')) t.problems.push(`${label}: body not in the frame`);
  await t.shot(shotName, `${label}: header fields over 256 KiB, the size notice in place of the folded fields; headers and body shown; fields.html directly HTTP ${f.status()}`, { full: false });
}
await fragments('round9-fields.eml (attachment)', `/attachments/${att['round9-fields.eml']}`,
  `/attachments/more_preview/${att['round9-fields.eml']}/fields.html`, `/attachments/more_preview/${att['round9-fields.eml']}/headers.html`, 'fragment-attachment');
await fragments('round9-fields.eml (repository)', `${R}/entry/round9-fields.eml`,
  `${R}/preview/round9-fields.eml@/fields.html`, `${R}/preview/round9-fields.eml@/headers.html`, 'fragment-repository');

// --- bed742c: a fields.html stored before the limit, revalidated
async function conditional(label, pageUrl, fieldsUrl, path) {
  await page(pageUrl);
  const first = await t.page.request.get(t.BASE + fieldsUrl);
  const etag = first.headers()['etag'];
  const again = await t.page.request.get(t.BASE + fieldsUrl, { headers: { 'If-None-Match': etag } });
  const mtime = fs.statSync(path).mtime;
  const original = fs.readFileSync(path);
  fs.writeFileSync(path, 'x'.repeat(262145)); fs.utimesSync(path, mtime, mtime);
  const old = await t.page.request.get(t.BASE + fieldsUrl, { headers: { 'If-None-Match': etag } });
  fs.writeFileSync(path, original); fs.utimesSync(path, mtime, mtime);
  note(`${label}: fields.html HTTP ${first.status()} ETag ${etag}; If-None-Match: HTTP ${again.status()}; the same file over 256 KiB, same mtime, If-None-Match: HTTP ${old.status()}`);
  if (first.status() !== 200 || again.status() !== 304) t.problems.push(`${label}: regular fragment ${first.status()}/${again.status()}`);
  if (old.status() !== 413) t.problems.push(`${label}: old oversized fragment HTTP ${old.status()}, expected 413`);
  return old.status();
}
const paths = JSON.parse(runner(`a = Attachment.find(${att['round9-plain.eml']}); r = Project.find_by!(identifier: "e2e-project").repositories.find_by!(identifier: "samples"); ` +
  `puts({ "attachment" => a.preview_assetpath(asset: "fields.html"), "repository" => r.preview_assetpath("round9-plain.eml", nil, asset: "fields.html") }.to_json)`));
const c1 = await conditional('round9-plain.eml (attachment)', `/attachments/${att['round9-plain.eml']}`, `/attachments/more_preview/${att['round9-plain.eml']}/fields.html`, paths.attachment);
const c2 = await conditional('round9-plain.eml (repository)', `${R}/entry/round9-plain.eml`, `${R}/preview/round9-plain.eml@/fields.html`, paths.repository);

// --- 6ce4793: an email beyond Cliff's limits keeps the page, cached and without the cache
async function huge(label, shotName) {
  const p = await page(`/attachments/${att['round9-huge.eml']}`);
  const frame = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['round9-huge.eml']}/index.html`);
  const reason = (p.body.match(/<p class="warning">([^<]*)<\/p>/) || [])[1];
  note(`${label}: page HTTP ${p.status}, reason ${JSON.stringify(reason)}, download link ${p.body.includes('/attachments/download/')}, preview frame ${/id="preview_(frame|object)"/.test(p.body)}; frame HTTP ${frame.status()}`);
  if (p.status !== 200 || !reason || !p.body.includes('/attachments/download/') || frame.status() !== 413) t.problems.push(`${label}: page ${p.status}, reason ${reason}, frame ${frame.status()}`);
  await t.go(`/attachments/${att['round9-huge.eml']}`, { allow: { requests: ['413 '] } });
  await t.page.waitForTimeout(1500); await t.page.mouse.move(0, 0);
  await t.shot(shotName, `${label}: the attachment page stays, with the reason above the frame (the frame answers 413)`, { full: false });
}
await huge('round9-huge.eml (1.2 MiB, Cliff max_size 1 MiB)', 'huge-cached');
runner('s = Setting.plugin_redmine_more_previews.to_h.deep_dup; s["cache_previews"] = "0"; Setting.plugin_redmine_more_previews = s');
await huge('round9-huge.eml without the cache', 'huge-uncached');
runner('s = Setting.plugin_redmine_more_previews.to_h.deep_dup; s["cache_previews"] = "1"; Setting.plugin_redmine_more_previews = s');

// --- reporter (no plugin permissions; the plugin's view permission is public)
await t.login('reporter');
const r1 = await page(`/attachments/${att['round9-fields.eml']}`);
const r2 = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['round9-fields.eml']}/fields.html`);
note(`reporter: round9-fields.eml page HTTP ${r1.status}, notice ${count(r1.body, NOTICE)}; fields.html HTTP ${r2.status()}`);
if (r1.status !== 200 || count(r1.body, NOTICE) !== 1 || r2.status() !== 413) t.problems.push('reporter: fragment');
await t.go(`/attachments/${att['round9-fields.eml']}`);
await t.page.waitForTimeout(1500); await t.page.mouse.move(0, 0);
await t.shot('reporter-fragment', 'reporter (core Reporter role): the same email, the notice in place of the fields', { full: false });

await sheet('results', 'Round 9 results', rows);

// clean up: the uploads, the repository files, the settings
await t.login('manager');
for (const name of Object.keys(att).filter(n => n.startsWith('round9'))) await t.page.request.delete(`${t.BASE}/attachments/${att[name]}.json`, { headers: H });
git('rm -q round9-fields.eml round9-plain.eml'); git("commit -q -m 'round 9: removed again'");
rails(`bundle exec rails runner ${process.cwd()}/test/e2e/seed.rb`);
await t.done();
