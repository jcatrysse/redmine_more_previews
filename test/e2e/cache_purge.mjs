// Round 6 (port of curecodejp cef06a3): the cache identity changed, so previews stored before are
// not served; the cache clean task removes them all once with DAYS=0 CONFIRM_PURGE_ALL=1 (refused
// without the confirmation). Previews are converted again on demand afterwards.
import { e2e } from '../../.codex/e2e/lib.mjs';
import { execSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';

const REDMINE = process.env.REDMINE_DIR;
const STORAGE = `${REDMINE}/tmp/more_previews`;
const t = await e2e('cache_purge');
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
const apiKey = () => ({ 'X-Redmine-API-Key': fs.readFileSync(`${REDMINE}/tmp/e2e-manager-api-key`, 'utf8').trim() });
const markers = () => execSync(`find ${STORAGE} -name '*.converter' | wc -l`).toString().trim();
function rake(env) {
  const r = spawnSync('bundle', ['exec', 'rake', 'redmine_more_previews:cache:clean'], { cwd: REDMINE, env: { ...process.env, RAILS_ENV: 'production', ...env } });
  return { status: r.status, out: (r.stdout.toString() + r.stderr.toString()).trim().split('\n').filter(l => !/warning:/i.test(l)).slice(-1)[0] || '' };
}

await t.login('manager');
const issue = (await (await t.page.request.get(`${t.BASE}/issues.json?project_id=e2e-project&subject=E2E%20previews`, { headers: apiKey() })).json()).issues[0];
const att = {};
for (const a of (await (await t.page.request.get(`${t.BASE}/issues/${issue.id}.json?include=attachments`, { headers: apiKey() })).json()).issue.attachments) att[a.filename] = a.id;
for (const name of ['sample.txt', 'sample.md', 'sample.zip']) await t.page.request.get(`${t.BASE}/attachments/more_preview/${att[name]}/index.${name.endsWith('.txt') ? 'txt' : 'html'}`);
// a preview stored before round 6: its marker is the converter id alone
const old = `${STORAGE}/attachments/999999/preview.html`;
fs.mkdirSync(old, { recursive: true });
fs.writeFileSync(`${old}/index.html`, 'stored before round 6');
fs.writeFileSync(`${old}.converter`, 'zippy');

const rows = [['step', 'exit', 'output', 'stored previews (markers)']];
rows.push(['before', '', '', markers()]);
const refused = rake({ DAYS: '0' });
rows.push(['DAYS=0 without CONFIRM_PURGE_ALL', refused.status, refused.out, markers()]);
if (refused.status === 0) t.problems.push('DAYS=0 without the confirmation was not refused');
const purged = rake({ DAYS: '0', CONFIRM_PURGE_ALL: '1' });
rows.push(['DAYS=0 CONFIRM_PURGE_ALL=1', purged.status, purged.out, markers()]);
if (purged.status !== 0 || markers() !== '0' || fs.existsSync(old)) t.problems.push(`purge: exit ${purged.status}, ${markers()} markers left`);
const again = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['sample.txt']}/index.txt`);
rows.push(['sample.txt previewed again', again.status(), (await again.text()).split('\n')[0], markers()]);
if (again.status() !== 200) t.problems.push(`after the purge: sample.txt HTTP ${again.status()}`);
await t.page.setContent(`<style>body{font:14px sans-serif;margin:24px}td,th{border:1px solid #ccc;padding:4px 8px;text-align:left}</style>` +
  `<h2>rake redmine_more_previews:cache:clean DAYS=0 (round 6)</h2><p>RAILS_ENV=production, in ${esc(REDMINE)}; one preview was planted with a marker of before round 6.</p>` +
  `<table><tr><th>${rows[0].map(esc).join('</th><th>')}</th></tr>` + rows.slice(1).map(r => `<tr><td>${r.map(esc).join('</td><td>')}</td></tr>`).join('') + '</table>');
await t.shot('rake', 'DAYS=0 is refused without CONFIRM_PURGE_ALL=1; with it every stored preview goes, and a preview is converted again on the next request', { full: false });
await t.done();
