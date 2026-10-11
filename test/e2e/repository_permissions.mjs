// Repository previews need "Browse repository" only (Jan, 2026-10-11, port of
// curecodejp 97f33d5): 'viewer' may view changesets but not browse the
// repository, and is refused the file content through the preview and its
// assets; reporter (browse_repository), outsider (non-member role) and anonymous
// on the public project are allowed, as core allows them the file page.
import { e2e } from '../../.codex/e2e/lib.mjs';

const t = await e2e('repository_permissions');
const R = '/projects/e2e-project/repository/samples';
const urls = [`${R}/preview/sample.md@/index.html`, `${R}/preview/sample.zip@inner/hello.txt`, `${R}/entry/sample.zip?asset=inner%2Fhello.txt`];

async function probe(user, want) {
  const rows = [];
  for (const u of urls) {
    const r = await t.page.request.get(t.BASE + u);
    rows.push(`${r.status()} ${u}`);
    if (r.status() !== want) t.problems.push(`${user} ${u}: HTTP ${r.status()}, expected ${want}`);
    if (want === 403 && (await r.text()).includes('hello inner')) t.problems.push(`${user} ${u}: file content returned`);
  }
  return rows;
}

await t.login('viewer');
await t.go(`${R}/revisions`);
await t.shot('viewer-revisions', 'viewer has "View changesets": the revisions of the repository are shown', { full: false });
await t.go(`${R}/entry/sample.md`, { status: 403 });
await t.shot('viewer-entry-refused', 'viewer without "Browse repository": the file page is refused by core (403)', { full: false });
const viewerRows = await probe('viewer', 403);

await t.login('reporter');
await t.go(`${R}/entry/sample.md`);
await t.page.waitForTimeout(1000); await t.page.mouse.move(0, 0);
await t.shot('reporter-entry', 'reporter (Browse repository): the markdown preview of the repository file is shown', { full: false });
const reporterRows = await probe('reporter', 200);

await t.login('outsider');
const outsiderRows = await probe('outsider', 200);

await t.page.setContent(`<h2>Repository preview and asset, per user</h2><pre>viewer (View changesets only):\n${viewerRows.join('\n')}\n\nreporter (Browse repository):\n${reporterRows.join('\n')}\n\noutsider (non-member, public project):\n${outsiderRows.join('\n')}</pre>`);
await t.shot('probes', 'Preview and asset URLs: 403 for viewer (it used to get the file through view_changesets), 200 for reporter and outsider', { full: false });

// anonymous follows core: the default Anonymous role has "Browse repository" on a public project
await t.anonymous();
await t.go(`${R}/entry/sample.md`);
await t.page.waitForTimeout(1000); await t.page.mouse.move(0, 0);
await t.shot('anonymous', 'Anonymous on the public project: core lets it browse the repository (default Anonymous role), so the preview is shown too', { full: false });
await t.done();
