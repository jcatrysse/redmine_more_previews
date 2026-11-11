// Round 10 (port of curecodejp 6.1.7 to 6.1.9), on files this scenario uploads to the
// issue "E2E previews" (e2e-project, public) and to an issue of e2e-private, and removes
// again; settings through rails runner, restored by the seed at the end:
// - Cliff (3b8a5ea): ISO-2022-JP base64 and Windows-1252 quoted-printable bodies shown in
//   their characters;
// - inline previews (77ce987, 0b3e950): deep markup keeps the page; the second view of a
//   large inline preview is not sanitized again (time of the page);
// - PDF downloads (31d1001): a converted PDF is named after its document, attachment and
//   repository file;
// - frames (5efeb83, add99bb): with <iframe> a PDF fills its pane (was a 16px strip) and
//   long text scrolls in its frame; text and PDF panes fit the window in both embeddings;
// - image previews (e1a2d25): an image beyond ImageMagick's limits shows the message;
// - Zippy (64315f4, 966c49d, ee6c728): an entry named index.html is served, the listing is
//   UTF-8 and its links open in the top window, a download from the frame works in the
//   private project;
// - Maggie (aa28b8b, 3f866f0, ours): the settings show the coders and the limit; HEIC,
//   HEIF and TIFF previewed once enabled; a HEIC declaring 100000x100000 answered 413 with
//   the message on the page; a HEIC lying about its size not decoded (address-space limit);
// - data: URIs (194c0b4): in the private project the image of a Libre docx and of a Cliff
//   email is shown in the frame (it was not: the frame sends no session cookie);
// - refusals: outsider on the private files, reporter (no plugin permissions) on public ones.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import zlib from 'node:zlib';

const REDMINE = process.env.REDMINE_DIR;
const t = await e2e('round10');
const env = { ...process.env, RAILS_ENV: process.env.RMP_SERVER_ENV || 'production' };
const rails = cmd => execSync(cmd, { cwd: REDMINE, env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }).trim();
const runner = ruby => rails(`bundle exec rails runner '${ruby.replace(/'/g, `'\\''`)}'`);
const H = { 'X-Redmine-API-Key': fs.readFileSync(`${REDMINE}/tmp/e2e-manager-api-key`, 'utf8').trim() };
const FIX = 'test/fixtures';
const rows = [];
const note = line => rows.push(line);
const settings = ruby => runner(`s = Setting.plugin_redmine_more_previews.to_h.deep_dup; ${ruby}; Setting.plugin_redmine_more_previews = s`);
const sheet = async (name, title, lines) => {
  await t.page.setContent(`<h2>${title}</h2><pre style="white-space:pre-wrap">${lines.join('\n').replace(/</g, '&lt;')}</pre>`);
  await t.shot(name, title, { full: false });
};
const frameOf = id => t.page.frames().find(f => f.url().includes(`/attachments/more_preview/${id}/`));
const settle = async (ms = 2500) => { await t.page.waitForTimeout(ms); await t.page.mouse.move(0, 0); };

// --- files
const b64 = s => Buffer.from(s).toString('base64');
const iso2022 = Buffer.from('1b2442467c4b5c386c244e4b5c4a382447243f1b2842', 'hex'); // 日本語の本文です in ISO-2022-JP
const jpEml = ['From: a@example.test', 'To: b@example.test', 'Subject: ROUND10-JP', 'MIME-Version: 1.0',
  'Content-Type: text/plain; charset=ISO-2022-JP', 'Content-Transfer-Encoding: base64', '', iso2022.toString('base64'), ''].join('\r\n');
const cp1252Eml = ['From: a@example.test', 'To: b@example.test', 'Subject: ROUND10-W1252', 'MIME-Version: 1.0',
  'Content-Type: text/html; charset=Windows-1252', 'Content-Transfer-Encoding: quoted-printable', '',
  '<p>ROUND10 caf=E9 na=EFve =80 5</p>', ''].join('\r\n');
const png = fs.readFileSync('test/fixtures/files/sample.png');
const cidEml = ['From: a@example.test', 'To: b@example.test', 'Subject: ROUND10-CID', 'MIME-Version: 1.0',
  'Content-Type: multipart/related; boundary="b1"', '', '--b1', 'Content-Type: text/html; charset=UTF-8', '',
  '<html><body><p>ROUND10 inline image</p><img src="cid:img1@x"></body></html>', '--b1',
  'Content-Type: image/png; name="image001.png"', 'Content-Transfer-Encoding: base64', 'Content-ID: <img1@x>',
  'Content-Disposition: inline; filename="image001.png"', '', png.toString('base64'), '--b1--', ''].join('\r\n');
const deep = 'h2. Deep\n\n' + '<div>'.repeat(500) + 'ROUND10-DEEP' + '</div>'.repeat(500) + '\n';
// about 200 KiB of html, below the 256 KiB limit: sanitized on the first view, kept after
const large = 'h2. Large\n\n' + Array.from({ length: 3500 }, (_, i) => `Paragraph ${i} with _emphasis_ ROUND10-LARGE.\n`).join('\n');
const longText = Array.from({ length: 400 }, (_, i) => `line ${i} ROUND10-LONG`).join('\n');
// a PNG ImageMagick refuses (width beyond 16KP) is made from the PNG header: 20000x1
const wide = (() => {
  const crc = buf => { let c, crcTable = []; for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; crcTable[n] = c >>> 0; }
    let x = 0xFFFFFFFF; for (const b of buf) x = crcTable[(x ^ b) & 0xFF] ^ (x >>> 8); return (x ^ 0xFFFFFFFF) >>> 0; };
  const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]);
    const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([len, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(20000, 0); ihdr.writeUInt32BE(1, 4); ihdr[8] = 8; ihdr[9] = 0;
  const raw = Buffer.alloc(20001); // filter byte + gray pixels
  return Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
})();
// a HEIC header declaring 100000x100000 (no image data: only the header is read)
const box = (type, payload = Buffer.alloc(0)) => { const s = Buffer.alloc(4); s.writeUInt32BE(8 + payload.length); return Buffer.concat([s, Buffer.from(type), payload]); };
const hugeHeic = (() => {
  const u32 = (...v) => { const b = Buffer.alloc(4 * v.length); v.forEach((x, i) => b.writeUInt32BE(x, 4 * i)); return b; };
  const ftyp = box('ftyp', Buffer.concat([Buffer.from('heic'), u32(0), Buffer.from('mif1heic')]));
  const ispe = box('ispe', u32(0, 100000, 100000));
  const ipma = Buffer.concat([u32(0, 1), Buffer.from([0, 1, 1, 0x81])]);
  const meta = box('meta', Buffer.concat([u32(0), box('hdlr', Buffer.concat([u32(0, 0), Buffer.from('pict'), Buffer.alloc(13)])),
    box('pitm', Buffer.concat([u32(0), Buffer.from([0, 1])])), box('iprp', Buffer.concat([box('ipco', ispe), box('ipma', ipma)]))]));
  return Buffer.concat([ftyp, meta, Buffer.alloc(64)]);
})();
const zipWithIndex = fs.readFileSync(execSync(`d=$(mktemp -d) && cd $d && printf 'the entry ROUND10' > index.html && mkdir 日本 && printf 'x' > 日本/ファイル.txt && zip -q -r round10.zip index.html 日本 && echo $d/round10.zip`, { encoding: 'utf8', shell: '/bin/bash' }).trim());

await t.anonymous();
const issueOf = async project => (await (await t.page.request.get(`${t.BASE}/issues.json?project_id=${project}&status_id=*`, { headers: H })).json()).issues.at(-1);
const pub = (await (await t.page.request.get(`${t.BASE}/issues.json?project_id=e2e-project&subject=E2E%20previews`, { headers: H })).json()).issues[0];
const priv = await issueOf('e2e-private');
const upload = async (issue, files) => {
  const uploads = [];
  for (const [filename, data, content_type] of files) {
    const up = await t.page.request.post(`${t.BASE}/uploads.json?filename=${encodeURIComponent(filename)}`, {
      headers: { ...H, 'Content-Type': 'application/octet-stream' }, data: Buffer.from(data) });
    if (up.status() !== 201) t.problems.push(`upload ${filename}: HTTP ${up.status()}`);
    uploads.push({ token: (await up.json()).upload.token, filename, content_type });
  }
  await t.page.request.put(`${t.BASE}/issues/${issue.id}.json`, { headers: { ...H, 'Content-Type': 'application/json' }, data: { issue: { uploads } } });
  const att = {};
  for (const a of (await (await t.page.request.get(`${t.BASE}/issues/${issue.id}.json?include=attachments`, { headers: H })).json()).issue.attachments) att[a.filename] = a.id;
  return att;
};
const att = await upload(pub, [
  ['round10-jp.eml', jpEml, 'message/rfc822'], ['round10-w1252.eml', cp1252Eml, 'message/rfc822'],
  ['round10-deep.textile', deep, 'text/x-web-textile'], ['round10-large.textile', large, 'text/x-web-textile'],
  ['round10-long.txt', longText, 'text/plain'], ['round10-wide.png', wide, 'image/png'],
  ['round10-index.zip', zipWithIndex, 'application/zip'], ['round10 Offerte.docx', fs.readFileSync(`${FIX}/files/sample_image.docx`), 'application/octet-stream'],
  ['round10-plain.heic', fs.readFileSync(`${FIX}/maggie/plain.heic`), 'image/heic'], ['round10-plain.heif', fs.readFileSync(`${FIX}/maggie/plain.heif`), 'image/heif'],
  ['round10-rotated.tif', fs.readFileSync(`${FIX}/maggie/rotated.tif`), 'image/tiff'], ['round10-huge.heic', hugeHeic, 'image/heic'],
  ['round10-lying.heic', fs.readFileSync(`${FIX}/maggie/lying-ispe.heic`), 'image/heic']]);
const patt = await upload(priv, [
  ['round10-private.docx', fs.readFileSync(`${FIX}/files/sample_image.docx`), 'application/octet-stream'],
  ['round10-private.eml', cidEml, 'message/rfc822'], ['round10-private.zip', zipWithIndex, 'application/zip']]);
runner('p = Project.find_by!(identifier: "e2e-private"); p.enabled_module_names = p.enabled_module_names | ["redmine_more_previews"]; p.save!');
settings('s["converter"]["libre"]["mime_types"]["docx"]["format"] = "html"');

const repoDir = `${REDMINE}/tmp/e2e-repo`;
const git = args => execSync(`git -C ${repoDir} -c user.name=E2E -c user.email=e2e@example.net ${args}`, { encoding: 'utf8' });
fs.copyFileSync(`${FIX}/files/sample.docx`, `${repoDir}/round10 report.docx`);
git("add 'round10 report.docx'"); git("commit -q -m 'round 10: docx'");
runner('Project.find_by!(identifier: "e2e-project").repositories.find_by!(identifier: "samples").fetch_changesets');
const R = '/projects/e2e-project/repository/samples';

await t.login('manager');

// --- Cliff charsets
for (const [name, want] of [['round10-jp.eml', '日本語の本文です'], ['round10-w1252.eml', 'café naïve € 5']]) {
  await t.go(`/attachments/${att[name]}`);
  await settle();
  const text = await frameOf(att[name])?.evaluate(() => document.body.innerText).catch(() => '') || '';
  note(`${name}: shows "${want}": ${text.includes(want)}`);
  if (!text.includes(want)) t.problems.push(`${name}: "${want}" not shown (${JSON.stringify(text.slice(0, 120))})`);
  await t.shot(name.replace('.eml', ''), `Cliff: ${name} shows "${want}" (was mojibake: the charset of the part was not converted)`, { full: false });
}

// --- inline: deep markup keeps the page; the large preview is sanitized once
await t.go(`/attachments/${att['round10-deep.textile']}`);
const deepBody = await t.page.content();
note(`deep textile: page 200, ROUND10-DEEP shown ${deepBody.includes('ROUND10-DEEP')}`);
await t.shot('inline-deep', 'Inline textile with 500 nested <div>: the page stays (Redmine 7 sanitizes with HTML4, which keeps it; under the HTML5 vendor it would show the "too complex" notice)', { full: false });
const timeOf = async url => { const t0 = Date.now(); const r = await t.page.request.get(t.BASE + url, { headers: { Accept: 'text/html' } }); await r.text(); return [r.status(), Date.now() - t0]; };
const views = [];
for (let i = 0; i < 4; i++) views.push(await timeOf(`/attachments/${att['round10-large.textile']}`));
note(`large inline preview (~200 KiB html), page views (status, ms): ${JSON.stringify(views)}`);
if (views.some(([s]) => s !== 200)) t.problems.push('large inline: not 200');
if (!(views[2][1] < views[0][1])) t.problems.push(`large inline: later view not faster ${JSON.stringify(views)}`);

// --- PDF download names
const libre = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['round10 Offerte.docx']}/index.pdf`);
settings('s["converter"]["libre"]["mime_types"]["docx"]["format"] = "pdf"');
const pdfA = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['round10 Offerte.docx']}/index.pdf`);
const pdfR = await t.page.request.get(`${t.BASE}${R}/preview/round10%20report.docx@/index.pdf`);
note(`PDF of "round10 Offerte.docx": HTTP ${pdfA.status()}, ${pdfA.headers()['content-disposition']}`);
note(`PDF of repository "round10 report.docx": HTTP ${pdfR.status()}, ${pdfR.headers()['content-disposition']}`);
if (!(pdfA.headers()['content-disposition'] || '').includes('round10%20Offerte.pdf') && !(pdfA.headers()['content-disposition'] || '').includes('round10 Offerte.pdf')) t.problems.push('attachment pdf name');
if (!(pdfR.headers()['content-disposition'] || '').includes('report.pdf')) t.problems.push('repository pdf name');

// --- frames, <object> (embedding 0) and <iframe> (embedding 1)
const frameInfo = () => t.page.evaluate(() => {
  const pane = document.querySelector('#preview_pane'); const f = document.querySelector('#preview_frame, #preview_object');
  return { tag: f?.tagName, paneH: Math.round(pane?.getBoundingClientRect().height), frameH: Math.round(f?.getBoundingClientRect().height), win: innerHeight, scrolling: f?.getAttribute('scrolling') };
});
for (const emb of ['0', '1']) {
  settings(`s["embedding"] = "${emb}"`);
  for (const name of ['round10-long.txt', 'round10 Offerte.docx']) {
    await t.go(`/attachments/${att[name]}`);
    await settle(4000);
    const info = await frameInfo();
    note(`embedding ${emb}, ${name}: ${JSON.stringify(info)}`);
    if (info.paneH !== info.win - 320) t.problems.push(`${emb} ${name}: pane ${info.paneH}, window ${info.win}`);
    if (info.frameH !== info.paneH) t.problems.push(`${emb} ${name}: frame ${info.frameH} of pane ${info.paneH}`);
    if (name.endsWith('.txt')) {
      const before = await t.page.evaluate(() => scrollY);
      await t.page.mouse.move(400, 400); await t.page.mouse.wheel(0, 2000); await t.page.waitForTimeout(600);
      const inner = await frameOf(att[name])?.evaluate(() => scrollY).catch(() => -1);
      const after = await t.page.evaluate(() => scrollY);
      note(`  wheel over the text: frame scrolled to ${inner}, page from ${before} to ${after}`);
      if (!(inner > 0)) t.problems.push(`${emb}: text frame did not scroll`);
    }
    await t.shot(`frame-${emb}-${name.endsWith('.txt') ? 'text' : 'pdf'}`, `${emb === '1' ? '<iframe>' : '<object>'}: ${name} in a pane of the window's height minus 320px${name.endsWith('.txt') ? ', scrolled inside its frame with the wheel' : ' (the PDF fills it; with <iframe> it was a 16px strip)'}`, { full: false });
  }
}
settings('s["embedding"] = "0"');

// --- image beyond ImageMagick's limits: the message instead of a broken image
await t.go(`/attachments/${att['round10-wide.png']}`, { allow: { requests: [`/attachments/more_preview/${att['round10-wide.png']}/index.jpg`] } });
await settle(4000);
const msg = await t.page.locator('img[onerror] + p.nodata').isVisible();
note(`round10-wide.png (20000x1): message visible ${msg}`);
if (!msg) t.problems.push('wide png: no message');
await t.shot('image-failed', 'Maggie: a PNG of 20000x1 pixels, beyond ImageMagick\'s 16,000: the message replaces the broken image', { full: false });

// --- Zippy: index.html entry, UTF-8, _top links, download in the private project
const listing = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['round10-index.zip']}/index.html`);
const lbody = await listing.text();
const entry = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['round10-index.zip']}/index.html?asset=index.html`);
note(`zip listing: ${listing.headers()['content-type']}, CSP ${listing.headers()['content-security-policy']}, _top links ${(lbody.match(/target="_top"/g) || []).length}`);
note(`zip entry index.html: HTTP ${entry.status()} "${(await entry.text()).slice(0, 30)}"`);
if (listing.headers()['content-type'] !== 'text/html; charset=utf-8') t.problems.push('listing charset');
if (entry.status() !== 200) t.problems.push('index.html entry');
await t.go(`/attachments/${att['round10-index.zip']}`);
await settle();
await t.shot('zip-index', 'Zippy: an archive with an entry index.html and a folder 日本 (UTF-8 listing); index.html is served as a download', { full: false });
await t.go(`/attachments/${patt['round10-private.zip']}`);
await settle();
const pframe = frameOf(patt['round10-private.zip']);
const [download] = await Promise.all([t.page.waitForEvent('download', { timeout: 10000 }).catch(() => null),
  pframe?.locator('a', { hasText: 'index.html' }).click().catch(() => null)]);
const dbody = download ? fs.readFileSync(await download.path(), 'utf8') : null;
note(`private zip: download from the frame ${download ? `"${dbody}" as ${download.suggestedFilename()}` : 'none'}; page stays ${t.page.url().endsWith(`/attachments/${patt['round10-private.zip']}`)}`);
if (dbody !== 'the entry ROUND10') t.problems.push(`private zip download: ${dbody}`);
await t.shot('zip-private', 'Zippy in e2e-private: clicking index.html in the sandboxed frame downloads the entry (target _top, the page stays)', { full: false });

// --- data: URIs in the private project
for (const [name, label] of [['round10-private.docx', 'Libre docx as HTML'], ['round10-private.eml', 'Cliff email with an inline image']]) {
  await t.go(`/attachments/${patt[name]}`);
  await settle(name.endsWith('.docx') ? 12000 : 3000);
  const imgs = await frameOf(patt[name])?.locator('img').evaluateAll(l => l.map(i => ({ src: i.getAttribute('src').slice(0, 22), w: i.naturalWidth }))).catch(() => []) || [];
  note(`${name} (e2e-private): images ${JSON.stringify(imgs)}`);
  if (!imgs.length || imgs.some(i => !i.src.startsWith('data:image/') || i.w === 0)) t.problems.push(`${name}: image not shown ${JSON.stringify(imgs)}`);
  await t.shot(name.replace('.', '-'), `${label} in e2e-private: the image is embedded as a data: URI and shown (it was not loaded in the frame before)`, { full: false });
}

// --- Maggie HEIC / HEIF / TIFF
await t.login('admin');
await t.go('/settings/plugin/redmine_more_previews');
const maggieSettings = await t.page.locator('text=Largest HEIC or TIFF image').count();
note(`settings: Maggie limit field ${maggieSettings}, HEIC/HEIF and TIFF coder lines ${await t.page.locator('text=HEIC/HEIF (convert)').count()} ${await t.page.locator('text=TIFF (convert)').count()}`);
await t.page.locator('text=HEIC/HEIF (convert)').scrollIntoViewIfNeeded().catch(() => {});
await t.shot('maggie-settings', 'Maggie settings: the HEIC/TIFF size limit (64 megapixels), and a check for the HEIC and TIFF coders of the ImageMagick Redmine runs', { full: false });
await t.login('manager');
const heicOff = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['round10-plain.heic']}/index.jpg`);
note(`HEIC before it is enabled: HTTP ${heicOff.status()} (off after the upgrade)`);
if (heicOff.status() === 200) t.problems.push('heic previewed while off');
settings('%w(heic heif tif tiff).each { |e| s["converter"]["maggie"]["mime_types"][e] = { "active" => "1", "format" => "jpg" } }');
for (const name of ['round10-plain.heic', 'round10-plain.heif', 'round10-rotated.tif']) {
  await t.go(`/attachments/${att[name]}`);
  await settle(3000);
  const ok = await t.page.locator('#preview_repository_entry_top + div img').evaluate(i => i.naturalWidth).catch(() => 0);
  note(`${name}: preview ${ok}px wide`);
  if (!ok) t.problems.push(`${name}: no preview`);
  await t.shot(name.replace(/\./g, '-'), `Maggie: ${name} previewed as jpg once enabled (first image, rotated as the file says)`, { full: false });
}
const huge = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['round10-huge.heic']}/index.jpg`);
note(`round10-huge.heic (declares 100000x100000): HTTP ${huge.status()} "${(await huge.text()).slice(0, 60)}"`);
if (huge.status() !== 413) t.problems.push(`huge heic: ${huge.status()}`);
await t.go(`/attachments/${att['round10-huge.heic']}`, { allow: { requests: ['413 '] } });
await settle(3000);
await t.shot('heic-huge', 'Maggie: a HEIC declaring 100000x100000 is refused with 413 before ImageMagick; the page shows the message', { full: false });
settings('s["converter"]["maggie"]["max_megapixels"] = "16"');
const lying = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['round10-lying.heic']}/index.jpg`);
note(`round10-lying.heic (declares 64x64, codes 9000x9000), limit 16 MP: HTTP ${lying.status()} (not decoded: address-space limit)`);
if (lying.status() === 200) t.problems.push('lying heic decoded');

// --- refusals
await t.login('outsider');
for (const name of Object.keys(patt)) {
  const r = await t.page.request.get(`${t.BASE}/attachments/more_preview/${patt[name]}/index.html`);
  note(`outsider: preview of ${name} HTTP ${r.status()}`);
  if (![403, 404].includes(r.status())) t.problems.push(`outsider ${name}: ${r.status()}`);
}
await t.go(`/attachments/${patt['round10-private.docx']}`, { status: 403 });
await t.shot('outsider', 'outsider (no membership): the private docx is refused (403)', { full: false });
await t.login('reporter');
await t.go(`/attachments/${att['round10-jp.eml']}`);
await settle();
await t.shot('reporter', 'reporter (core Reporter role, no plugin permissions; the view permission is public): the ISO-2022-JP email is shown', { full: false });

await sheet('results', 'Round 10 results', rows);

// clean up: the uploads, the repository file, the settings and the module of e2e-private
await t.login('manager');
for (const id of [...Object.entries(att).filter(([n]) => n.startsWith('round10')), ...Object.entries(patt)].map(([, id]) => id)) {
  await t.page.request.delete(`${t.BASE}/attachments/${id}.json`, { headers: H });
}
git("rm -q 'round10 report.docx'"); git("commit -q -m 'round 10: removed again'");
runner('p = Project.find_by!(identifier: "e2e-private"); p.enabled_module_names = p.enabled_module_names - ["redmine_more_previews"]; p.save!');
rails(`bundle exec rails runner ${process.cwd()}/test/e2e/seed.rb`);
await t.done();
