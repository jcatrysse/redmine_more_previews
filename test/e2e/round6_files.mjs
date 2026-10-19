// Round 6 (port of curecodejp 6.1.3), the smaller user-visible changes on the files of the
// issue "E2E round 6" (test/e2e/seed.rb):
// - Vince: the IMPP field has a label, PHOTO an alternative text (a3bb8af, e0f27cd, 3906119);
// - Cliff: the labels of the header box stay on one line, also in German (2bec017);
// - Mark: a file named "-draft.md" is previewed (a4d7616: mv took the name for an option);
// - an attachment whose file is gone from disk: 404 for every preview URL, not 500 (128e9db).
import { e2e } from '../../.codex/e2e/lib.mjs';
import fs from 'node:fs';
import { execSync } from 'node:child_process';

const REDMINE = process.env.REDMINE_DIR;
const t = await e2e('round6_files');
const apiKey = () => ({ 'X-Redmine-API-Key': fs.readFileSync(`${REDMINE}/tmp/e2e-manager-api-key`, 'utf8').trim() });
async function attachments(subject) {
  const issue = (await (await t.page.request.get(`${t.BASE}/issues.json?project_id=e2e-project&subject=${encodeURIComponent(subject)}`, { headers: apiKey() })).json()).issues[0];
  const att = {};
  for (const a of (await (await t.page.request.get(`${t.BASE}/issues/${issue.id}.json?include=attachments`, { headers: apiKey() })).json()).issue.attachments) att[a.filename] = a.id;
  return att;
}

await t.login('manager');
const att = { ...(await attachments('E2E round 6')), ...(await attachments('E2E previews')) };

// --- Vince
const card = await (await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['impp.vcf']}/index.html`)).text();
if (!/<label[^>]*>\s*Instant messaging\s*<\/label>/.test(card)) t.problems.push('vcard: no "Instant messaging" label');
if (/translation missing/i.test(card)) t.problems.push('vcard: "translation missing" in the card');
if (!/<img[^>]*alt="Photo"/.test(card)) t.problems.push('vcard: the photo has no alt="Photo"');
await t.go(`/attachments/${att['impp.vcf']}`, { allow: { js: ['has been blocked by CORS policy'] } });
await t.page.waitForTimeout(1500);
await t.page.mouse.move(0, 0);
await t.shot('vcard', 'impp.vcf: the IMPP address is labelled "Instant messaging" (it read "Translation missing" before); the photo carries alt="Photo"', { full: false });

// --- Cliff's header labels, in German (the manager's language switched and back)
async function language(lang) {
  await t.go('/my/account');
  await t.page.selectOption('#user_language', lang);
  await t.page.click('#my_account_form input[type=submit], input[name=commit]');
  await t.settle();
}
await language('de');
await t.go(`/attachments/${att['sample.eml']}`);
await t.page.waitForTimeout(1500);
const labels = await t.page.locator('#preview_repository_entry_top .box td[style*="font-weight"]').evaluateAll(tds =>
  tds.map(td => ({ text: td.textContent.trim(), lines: Math.round(td.getBoundingClientRect().height / parseFloat(getComputedStyle(td).lineHeight || '20')), wrap: getComputedStyle(td).whiteSpace })));
if (labels.length < 4) t.problems.push(`email headers: ${labels.length} labels`);
for (const l of labels) if (l.wrap !== 'nowrap' || l.lines > 1) t.problems.push(`email header label "${l.text}": white-space ${l.wrap}, ${l.lines} lines`);
await t.shot('mail-labels-de', `sample.eml as a German-speaking user: the labels (${labels.map(l => l.text).join(', ')}) stay on one line`, { full: false });
await language('en');

// --- Mark: a name that starts with a dash
const draft = await t.page.request.get(`${t.BASE}/attachments/more_preview/${att['-draft.md']}/index.html`);
const draftBody = await draft.text();
if (draft.status() !== 200 || !draftBody.includes('starts with a dash')) t.problems.push(`-draft.md: HTTP ${draft.status()}`);
await t.go(`/attachments/${att['-draft.md']}`);
await t.page.waitForTimeout(1500);
await t.shot('draft', '-draft.md is previewed by Mark (pandoc); before, "mv -draft.html ..." took the name for an option and the preview was empty', { full: false });

// --- a file gone from disk
const disk = execSync(`cd ${REDMINE} && RAILS_ENV=production bundle exec rails runner 'print Attachment.find(${att['gone.txt']}).diskfile'`).toString().trim();
if (fs.existsSync(disk)) fs.renameSync(disk, `${disk}.e2e-away`);
const goneRows = [];
for (const url of [`/attachments/more_preview/${att['gone.txt']}/index.txt`, `/attachments/more_preview/${att['gone.txt']}/index.txt?reload=1`]) {
  const r = await t.page.request.get(t.BASE + url);
  goneRows.push(`${url}: ${r.status()}`);
  if (r.status() !== 404) t.problems.push(`gone.txt ${url}: HTTP ${r.status()}, expected 404`);
}
await t.go(`/attachments/${att['gone.txt']}`, { status: 404 });
await t.shot('gone', `gone.txt with its file removed from disk: the page and the preview URLs answer 404 (${goneRows.join('; ')}), as Redmine's own download`, { full: false });
fs.renameSync(`${disk}.e2e-away`, disk);
await t.done();
