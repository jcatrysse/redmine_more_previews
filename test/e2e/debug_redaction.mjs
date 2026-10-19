// Round 6 (port of curecodejp d704e5d, 35fdcb6, 554a683): with "debug" on, a preview shows
// public converter metadata only (no paths, request, settings, instance variables); the
// preview stored without debug is not served for it, and a browser holding its ETag gets the
// debug preview, not a 304. Debug off again: the real preview returns.
import { e2e } from '../../.codex/e2e/lib.mjs';
import fs from 'node:fs';

const REDMINE = process.env.REDMINE_DIR;
const t = await e2e('debug_redaction');
const apiKey = () => ({ 'X-Redmine-API-Key': fs.readFileSync(`${REDMINE}/tmp/e2e-manager-api-key`, 'utf8').trim() });
async function setDebug(on) {
  await t.go('/settings/plugin/redmine_more_previews');
  await t.sudo();
  const box = t.page.locator('input[name="settings[debug]"][type=checkbox]');
  if ((await box.isChecked()) !== on) await box.click();
  await t.page.click('#settings form input[type=submit], form[action$="redmine_more_previews"] input[type=submit]');
  await t.settle();
  await t.sudo();
  if (!(await t.page.locator('#flash_notice').count())) t.problems.push(`debug ${on}: settings not saved`);
}

await t.login('admin');
const issue = (await (await t.page.request.get(`${t.BASE}/issues.json?project_id=e2e-project&subject=E2E%20previews`, { headers: apiKey() })).json()).issues[0];
const att = {};
for (const a of (await (await t.page.request.get(`${t.BASE}/issues/${issue.id}.json?include=attachments`, { headers: apiKey() })).json()).issue.attachments) att[a.filename] = a.id;
const url = `/attachments/more_preview/${att['sample.txt']}/index.txt`;

await t.login('manager');
await t.page.request.get(t.BASE + url);
const normal = await t.page.request.get(t.BASE + url);
const etag = normal.headers()['etag'];
const cached = await t.page.request.get(t.BASE + url, { headers: { 'If-None-Match': etag } });
if (cached.status() !== 304) t.problems.push(`same ETag without debug: HTTP ${cached.status()}, expected 304`);

await t.login('admin');
await setDebug(true);
await t.login('manager');
const debug = await t.page.request.get(t.BASE + url, { headers: { 'If-None-Match': etag } });
const body = await debug.text();
if (debug.status() !== 200) t.problems.push(`debug with the old ETag: HTTP ${debug.status()}, expected 200`);
if (!body.includes('Converter debug information')) t.problems.push('debug preview: no "Converter debug information"');
for (const secret of [REDMINE, '/tmp/', 'more_previews', '@request', '@settings', 'e2e-project', 'Plain text sample']) {
  if (body.includes(secret)) t.problems.push(`debug preview shows "${secret}"`);
}
await t.go(`/attachments/${att['sample.txt']}`);
await t.page.waitForTimeout(1500);
await t.shot('debug-page', 'Debug on: the preview of sample.txt shows converter, versions, source type and format only; no path, request, settings or file content', { full: false });
await t.page.setContent(`<pre style="font:13px monospace;margin:24px">HTTP ${debug.status()} (request with the ETag of the normal preview: ${etag})\n\n${body.replace(/&/g, '&amp;').replace(/</g, '&lt;')}</pre>`);
await t.shot('debug-body', 'The debug preview, answered with 200 to a browser holding the ETag of the normal preview: the whole body', { full: false });

await t.login('admin');
await setDebug(false);
await t.login('manager');
const back = await (await t.page.request.get(t.BASE + url)).text();
if (!back.includes('Plain text sample')) t.problems.push('debug off: the real preview did not return');
await t.go(`/attachments/${att['sample.txt']}`);
await t.page.waitForTimeout(1500);
await t.shot('normal-again', 'Debug off: the real preview of sample.txt again', { full: false });
await t.done();
