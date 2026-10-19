// Round 6 (port of curecodejp 504c42f #37, a213a44 #36) on the repository "round6" of
// e2e-project (test/e2e/seed.rb), deleted at the end (start_server.sh creates it again):
// - the email at the top of the repository lists its attachment with a working link (the
//   link read /preview/./with-attachment.eml@... before, a 404);
// - deleting the repository removes its previews from tmp/more_previews (they stayed for good);
//   the other repository's previews stay.
import { e2e } from '../../.codex/e2e/lib.mjs';
import fs from 'node:fs';

const REDMINE = process.env.REDMINE_DIR;
const t = await e2e('repository_delete');
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
async function table(title, intro, rows) {
  await t.page.setContent(`<style>body{font:14px sans-serif;margin:24px}td,th{border:1px solid #ccc;padding:4px 8px;text-align:left}</style>` +
    `<h2>${esc(title)}</h2><p>${esc(intro)}</p><table><tr><th>${rows[0].map(esc).join('</th><th>')}</th></tr>` +
    rows.slice(1).map(r => `<tr><td>${r.map(esc).join('</td><td>')}</td></tr>`).join('') + '</table>');
}

await t.login('manager');
// the box lists an attachment with a link once the preview frame stored it (as before)
await t.go('/projects/e2e-project/repository/round6/entry/with-attachment.eml');
await t.page.waitForTimeout(2000);
await t.go('/projects/e2e-project/repository/round6/entry/with-attachment.eml');
await t.page.waitForTimeout(1500);
const link = t.page.locator('#preview_repository_entry_top .box a', { hasText: 'note.txt' });
if (!(await link.count())) t.problems.push('email: no link to note.txt in the attachments box');
const href = (await link.first().getAttribute('href').catch(() => '')) || '';
if (href.includes('/./')) t.problems.push(`email: the link holds "/./": ${href}`);
const note = href ? await t.page.request.get(t.BASE + href) : null;
if (!note || note.status() !== 200 || !(await note.text()).includes('E2E-NOTE')) t.problems.push(`email: ${href} answers ${note && note.status()}`);
await t.shot('email-attachment', `with-attachment.eml at the top of the repository: the attachment note.txt links to ${href} (HTTP ${note && note.status()})`, { full: false });
// a preview of the other repository, which must stay
await t.page.request.get(`${t.BASE}/projects/e2e-project/repository/samples/preview/sample.txt@/index.txt`);

const storage = `${REDMINE}/tmp/more_previews/repository/gits`;
await t.login('admin');
await t.go('/projects/e2e-project/settings/repositories');
await t.sudo();
const row = t.page.locator('table.list tr', { hasText: 'round6' });
const deleteLink = row.locator('a.icon-del, a[data-method="delete"]');
const id = ((await deleteLink.getAttribute('href').catch(() => '')) || '').match(/repositories\/(\d+)/)?.[1];
const samplesId = ((await t.page.locator('table.list tr', { hasText: 'samples' }).locator('a.icon-del, a[data-method="delete"]').getAttribute('href').catch(() => '')) || '').match(/repositories\/(\d+)/)?.[1];
const before = id && fs.existsSync(`${storage}/${id}`);
if (!before) t.problems.push(`no previews of repository ${id} in ${storage} before the deletion`);
await t.shot('settings', `Project settings > Repositories: "round6" (id ${id}) is about to be deleted; its previews are in tmp/more_previews/repository/gits/${id}`, { full: false });
t.page.once('dialog', d => d.accept());
await deleteLink.click();
await t.settle();
await t.sudo();
t.check('delete repository');
const rows = [['previews', 'before', 'after']];
const after = id && fs.existsSync(`${storage}/${id}`);
rows.push([`repository/gits/${id} (round6, deleted)`, before ? 'present' : 'missing', after ? 'STILL THERE' : 'removed']);
rows.push([`repository/gits/${id}.cleanup_pending`, '', fs.existsSync(`${storage}/${id}.cleanup_pending`) ? 'STILL THERE' : 'none']);
const samplesKept = samplesId && fs.existsSync(`${storage}/${samplesId}`);
rows.push([`repository/gits/${samplesId} (samples, kept)`, 'present', samplesKept ? 'present' : 'REMOVED']);
if (after) t.problems.push(`the previews of repository ${id} stayed after its deletion`);
if (fs.existsSync(`${storage}/${id}.cleanup_pending`)) t.problems.push('a cleanup is still pending');
if (!samplesKept) t.problems.push('the previews of the other repository were removed');
await t.shot('deleted', 'The repository "round6" is deleted', { full: false });
await table('Preview cache when a repository is deleted', 'Upstream 504c42f (#37): removed once the deletion is committed.', rows);
await t.shot('cache', 'Its previews are removed with it, the other repository\'s stay', { full: false });
await t.done();
