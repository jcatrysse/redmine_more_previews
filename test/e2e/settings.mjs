// The plugin's settings (admin): global options and the converters with their
// file types and formats. Switches to the <iframe> embedding and off the cache
// and shows a preview still works, shows the warning for a file type claimed by
// two converters, and the refusal for a non-admin. Restores the settings.
import { e2e } from '../../.codex/e2e/lib.mjs';

const t = await e2e('settings');
const URL = '/settings/plugin/redmine_more_previews';

await t.login('admin');
await t.go(URL);
await t.sudo();
if (!(await t.page.locator('input[name="settings[converter][libre][active]"]:checked').count())) t.problems.push('libre not shown active');
const ok = await t.page.locator('#converter_mark .icon-ok svg, #converter_libre .icon-ok svg').count();
if (!ok) t.problems.push('converter status has no SVG icon');
await t.shot('page', 'Settings: global options, then one box per converter with its logo, program check (pandoc, LibreOffice ... available, SVG icon) and file types');

async function save(step) {
  await t.page.click('#settings form input[type=submit], form[action$="redmine_more_previews"] input[type=submit]');
  await t.settle();
  await t.sudo();
  if (!(await t.page.locator('#flash_notice').count())) t.problems.push(`${step}: no "Successful update"`);
  t.check(step);
}

// help text toggles
await t.page.locator('#content a.icon-help').first().click();
if (!(await t.page.locator('#help_redmine_more_previews_embed_settings').isVisible())) t.problems.push('help text does not open');
await t.shot('help', 'The help link (SVG icon) opens the explanation of the embedding option', { full: false });

// iframe embedding and no cache
await t.page.check('input[name="settings[embedding]"][value="1"]');
await t.page.uncheck('input[name="settings[cache_previews]"]');
await save('iframe and no cache');

const issues = await (await t.page.request.get(`${t.BASE}/issues.json?project_id=e2e-project&subject=E2E%20previews`)).json();
const att = {};
for (const a of (await (await t.page.request.get(`${t.BASE}/issues/${issues.issues[0].id}.json?include=attachments`)).json()).issue.attachments) att[a.filename] = a.id;
await t.go(`/attachments/${att['sample.odt']}`);
await t.page.waitForTimeout(2000);
if (!(await t.page.locator('iframe#preview_frame').count())) t.problems.push('iframe embedding not used');
if (await t.page.locator('#ajax-indicator').isVisible()) t.problems.push('ajax indicator still visible after the frame loaded');
const frame = t.page.frames().find(f => f.url().includes('/more_preview/'));
if (!frame || !(await frame.locator('text=Office sample').count())) t.problems.push('iframe preview empty');
await t.page.mouse.move(0, 0);
await t.shot('iframe-no-cache', 'With <iframe> embedding and the cache off the odt is converted on every request and shown; the loading indicator is hidden on load (jQuery 3 .on("load"), no JS error)', { full: false });

// a file type claimed by two converters
await t.go(URL);
await t.page.check('input[name="settings[converter][nil_text][active]"]');
await t.page.check('input[name="settings[converter][nil_text][mime_types][txt][active]"]');
await save('nil_text txt');
const warn = t.page.locator('#converter_nil_text .flash.warning');
if (!(await warn.count())) t.problems.push('no warning for .txt claimed by nil_text and teddie');
await warn.first().scrollIntoViewIfNeeded().catch(() => {});
await t.shot('double', '.txt active in both Nil Text and Teddie: the row is marked as a warning', { full: false });

// restore what the seed set
await t.page.uncheck('input[name="settings[converter][nil_text][mime_types][txt][active]"]');
await t.page.uncheck('input[name="settings[converter][nil_text][active]"]');
await t.page.check('input[name="settings[embedding]"][value="0"]');
await t.page.check('input[name="settings[cache_previews]"]');
await save('restore');

// refusals
await t.login('manager');
await t.go(URL, { status: 403 });
await t.shot('manager-refused', 'A non-admin (manager) gets 403 on the plugin settings', { full: false });
await t.anonymous();
await t.go(URL);
if (!t.page.url().includes('/login')) t.problems.push(`anonymous: ${t.page.url()}`);
await t.shot('anonymous-login', 'Anonymous is sent to the login page', { full: false });
await t.done();
