// Combined run with redmine_contacts_helpdesk only: a customer's email is stored as
// message.eml on its helpdesk ticket, so whoever writes to the helpdesk controls a file
// that staff preview with Cliff. test/e2e/seed.rb lets two hostile emails arrive through
// HelpdeskMailer.receive (150 nested multipart parts, 1,001 parts); their previews must
// be refused with the reason at once, and the server must keep answering.
// Without the helpdesk plugin the scenario has nothing to look at and says so.
import { e2e } from '../../.codex/e2e/lib.mjs';
import fs from 'node:fs';
import { execSync } from 'node:child_process';

const t = await e2e('helpdesk_mail');
await t.login('manager');
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
const issues = (await (await t.page.request.get(`${t.BASE}/issues.json?project_id=e2e-project&subject=~E2E%20hostile%20mail&status_id=*`, { headers: apiKey() })).json()).issues || [];
if (!issues.length) {
  console.log('helpdesk_mail: no hostile helpdesk tickets (redmine_contacts_helpdesk not installed), nothing to check');
  await t.done();
  process.exit(0);
}
if (issues.length !== 2) t.problems.push(`expected 2 hostile tickets, found ${issues.length}`);

const rows = [['ticket', 'attachment', 'HTTP', 'seconds', 'preview', 'other request meanwhile']];
for (const issue of issues.sort((a, b) => a.id - b.id)) {
  // the helpdesk attaches the email to the ticket's HelpdeskTicket, not to the issue
  const found = execSync(`bundle exec rails runner -e production "a = HelpdeskTicket.find_by(issue_id: ${issue.id})&.attachments&.find_by(filename: 'message.eml'); puts [a&.id, a&.filesize].join(' ')"`,
    { cwd: process.env.REDMINE_DIR }).toString().trim().split('\n').pop().split(' ');
  const eml = found[0] ? { id: Number(found[0]), filesize: Number(found[1]) } : null;
  if (!eml) { t.problems.push(`#${issue.id}: no message.eml`); continue; }
  const started = Date.now();
  const [r, other] = await Promise.all([
    t.page.request.get(`${t.BASE}/attachments/more_preview/${eml.id}/index.html`, { timeout: 120000 }),
    t.page.request.get(`${t.BASE}/my/page`),
  ]);
  const seconds = ((Date.now() - started) / 1000).toFixed(1);
  const body = await r.text();
  const want = issue.subject.endsWith('nested') ? 'more than 100 nested multipart parts' : 'more than 1000 parts';
  rows.push([`#${issue.id} ${issue.subject}`, `message.eml (${eml.filesize} bytes)`, r.status(), seconds, body.slice(0, 70), `HTTP ${other.status()}`]);
  if (!body.includes(want)) t.problems.push(`#${issue.id}: preview lacks "${want}": ${body.slice(0, 200)}`);
  if (Number(seconds) > 10) t.problems.push(`#${issue.id}: the refusal took ${seconds} s`);
  if (other.status() !== 200) t.problems.push(`#${issue.id}: the server did not answer another request (${other.status()})`);
  await t.go(`/attachments/${eml.id}`);
  await t.page.waitForTimeout(1500);
  await t.page.mouse.move(0, 0);
  await t.shot(`ticket-${issue.subject.split(' ').pop()}`, `The message.eml of the helpdesk ticket "${issue.subject}": the preview says why the email is not previewed`, { full: false });
}
await t.page.setContent(`<style>body{font:14px sans-serif;margin:24px}td,th{border:1px solid #ccc;padding:4px 8px;text-align:left}</style>` +
  `<h2>Hostile customer emails on helpdesk tickets, as manager</h2><p>Each stored email is refused with its reason at once; a request for /my/page sent at the same time is answered.</p>` +
  `<table><tr><th>${rows[0].map(esc).join('</th><th>')}</th></tr>${rows.slice(1).map(r => `<tr><td>${r.map(esc).join('</td><td>')}</td></tr>`).join('')}</table>`);
await t.shot('results', 'Both hostile message.eml files are refused at once, the server keeps answering', { full: false });
await t.go(`/issues/${issues[0].id}`);
await t.shot('ticket', 'The helpdesk ticket the nested hostile email created (its message.eml is stored with the ticket and previewed above)', { full: false });
await t.done();

// lookups through the manager's API key (test/e2e/seed.rb): a plugin may restrict issue data for a session
function apiKey() {
  return { 'X-Redmine-API-Key': fs.readFileSync(`${process.env.REDMINE_DIR}/tmp/e2e-manager-api-key`, 'utf8').trim() };
}
