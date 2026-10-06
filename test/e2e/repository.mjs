// Previews of files in a repository (RepositoriesController#entry and the
// plugin's more_preview / more_asset routes), as the manager; a zip in the
// repository lists its files and serves them.
import { e2e } from '../../.codex/e2e/lib.mjs';

const t = await e2e('repository');
await t.login('manager');
const R = '/projects/e2e-project/repository/samples';
const fonts = { js: ['has been blocked by CORS policy'] }; // vcard: see converters.mjs

for (const [path, caption, allow] of [
  ['sample.md', 'Markdown file in the repository, converted by Mark'],
  ['docs/sample.docx', 'docx in a folder of the repository, converted to PDF by LibreOffice (no PDF viewer in headless Chromium; checked through its URL)'],
  ['sample.vcf', 'vcard in the repository', fonts],
  ['sample.txt', 'Text file in the repository (Teddie)'],
  ['sample.zip', 'Zip in the repository: its files are listed (the preview was empty before this branch)'],
]) {
  await t.go(`${R}/entry/${path}`, { allow });
  if (!(await t.page.locator('#preview_repository_entry_top').count())) t.problems.push(`${path}: no plugin preview`);
  await t.page.waitForTimeout(1500); await t.page.mouse.move(0, 0);
  t.check(path, allow);
  await t.shot(path.replace(/[/.]/g, '-'), caption, { full: false });
}
const pdf = await t.page.request.get(`${t.BASE}${R}/preview/docs/sample.docx@/index.pdf`);
if (pdf.status() !== 200 || !(await pdf.body()).toString('latin1').startsWith('%PDF')) t.problems.push(`docx pdf: HTTP ${pdf.status()}`);
const zipFrame = t.page.frames().find(f => f.url().includes('/preview/sample.zip@/index.html'));
if (!zipFrame || !(await zipFrame.locator('a', { hasText: 'hello.txt' }).count())) t.problems.push('zip table empty');
const asset = await t.page.request.get(`${t.BASE}${R}/preview/sample.zip@/index.html?asset=inner%2Fhello.txt`);
if ((await asset.text()) !== 'hello inner\n') t.problems.push('zip asset in repository: wrong content');

// a role with "Browse repository" but without "View changesets": reporter role has both in default data,
// so the check runs in the integration tests (test_more_preview_is_allowed_with_browse_repository_alone).
await t.login('outsider');
await t.go(`${R}/entry/sample.md`, { status: 200 }); // public project, non-member role
await t.page.waitForTimeout(1000);
await t.shot('outsider-public', 'Outsider on the public project (non-member role) can browse and preview the repository like core allows', { full: false });
await t.done();
