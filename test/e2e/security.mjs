// Failure paths: an asset outside the preview directory (used to return any
// file the server could read), a file type without converter, a non-numeric id,
// and the sandbox header on an HTML preview.
import { e2e } from '../../.codex/e2e/lib.mjs';
import fs from 'node:fs';

const t = await e2e('security');
await t.login('reporter');
const att = {};
const pub = (await (await t.page.request.get(`${t.BASE}/issues.json?project_id=e2e-project&subject=E2E%20previews`, { headers: e2eApiKey() })).json()).issues[0];
for (const a of (await (await t.page.request.get(`${t.BASE}/issues/${pub.id}.json?include=attachments`, { headers: e2eApiKey() })).json()).issue.attachments) att[a.filename] = a.id;

const rows = [];
async function probe(path, want, mustNotContain) {
  const r = await t.page.request.get(t.BASE + path);
  const body = await r.text();
  const bad = mustNotContain && body.includes(mustNotContain);
  rows.push(`${r.status()} ${path}${bad ? '  LEAK' : ''}`);
  if (r.status() !== want || bad) t.problems.push(`${path}: HTTP ${r.status()}${bad ? ' and the file content' : ''}`);
}
const up = '../'.repeat(12);
await probe(`/attachments/more_preview/${att['sample.txt']}/index.txt?asset=${up}etc/passwd`, 404, 'root:');
await probe(`/attachments/more_preview/${att['sample.zip']}/index.html?asset=${up}config/database.yml`, 404, 'adapter');
await probe(`/attachments/more_preview/${att['sample.md']}/index.html?asset=/etc/passwd`, 404, 'root:');
await probe(`/attachments/more_preview/${att['sample.txt']}/..%2F..%2F..%2F..%2F..%2F..%2Fconfig%2Fdatabase.yml`, 404, 'adapter');
await probe(`/projects/e2e-project/repository/samples/entry/sample.zip?asset=${up}etc/passwd`, 404, 'root:');
await probe(`/projects/e2e-project/repository/samples/preview/sample.zip@/index.html?asset=${up}etc/passwd`, 404, 'root:');
await probe(`/attachments/more_preview/999999/index.html`, 404);

// the refusal itself has no body (404 for a non-HTML format), so show the probe results
await t.go(`/attachments/more_preview/${att['sample.txt']}/index.txt?asset=${up}etc/passwd`, { status: 404 })
  .catch(e => t.problems.push(`traversal in the browser: ${String(e.message).split('\n')[0]} (the file is served)`));
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
await t.page.setContent(`<h2>Path traversal probes as reporter</h2><p>HTTP status and URL; "LEAK" would mark a response carrying the file.</p><pre>${esc(rows.join('\n'))}</pre>`);
await t.shot('traversal-404', 'Assets outside the preview directory are refused with 404 (before this branch /etc/passwd and config/database.yml came back with 200)', { full: false });

const r = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['sample.html']}/index.html`);
const csp = r.headers()['content-security-policy'] || '';
if (!csp.startsWith('sandbox') || csp.includes('allow-scripts') || csp.includes('allow-same-origin')) t.problems.push(`html preview CSP: "${csp}"`);
if (r.headers()['x-content-type-options'] !== 'nosniff') t.problems.push('no nosniff');
await t.go(`/attachments/more_preview/${att['sample.html']}/index.html`);
await t.shot('sandbox', `An HTML preview opened directly: rendered, but with "Content-Security-Policy: ${csp}" (no script, opaque origin)`, { full: false });
await t.done();

// lookups through the manager's API key (test/e2e/seed.rb): a plugin may restrict issue data for a session
function e2eApiKey() {
  return { 'X-Redmine-API-Key': fs.readFileSync(`${process.env.REDMINE_DIR}/tmp/e2e-manager-api-key`, 'utf8').trim() };
}
