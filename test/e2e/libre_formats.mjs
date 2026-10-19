// Round 6 (port of curecodejp f06370c, 4540b78): a LibreOffice format that the file type does
// not offer is refused when the settings are saved, with a translated error, and nothing is
// saved. The page offers only valid formats, so the scenario adds a forged option first, as a
// hand-made request would.
import { e2e } from '../../.codex/e2e/lib.mjs';

const t = await e2e('libre_formats');
const URL = '/settings/plugin/redmine_more_previews';
const SELECT = 'select[name="settings[converter][libre][mime_types][docx][format]"]';

async function forge(value) {
  await t.go(URL);
  await t.sudo();
  const before = await t.page.inputValue(SELECT);
  await t.page.evaluate(([sel, v]) => { const s = document.querySelector(sel); const o = new Option(v, v); s.add(o); s.value = v; }, [SELECT, value]);
  await t.page.click('#settings form input[type=submit], form[action$="redmine_more_previews"] input[type=submit]');
  await t.settle();
  await t.sudo();
  return before;
}

await t.login('admin');
for (const [value, label] of [['xml', 'an unknown format'], ['pdf;touch /tmp/e2e-pwned', 'shell metacharacters']]) {
  const before = await forge(value);
  const error = (await t.page.locator('#flash_error').textContent().catch(() => '')) || '';
  if (!error.includes('Invalid LibreOffice conversion format')) t.problems.push(`${label}: no error ("${error}")`);
  if (await t.page.locator('#flash_notice').count()) t.problems.push(`${label}: "Successful update" shown`);
  const after = await t.page.inputValue(SELECT);
  if (after !== before) t.problems.push(`${label}: docx format changed from ${before} to ${after}`);
  await t.shot(value === 'xml' ? 'refused-en' : 'refused-shell', `docx -> "${value}" (${label}): refused, "Invalid LibreOffice conversion format; settings were not saved.", docx stays ${before}`, { full: false });
}

// the same in the user's language (the admin switches to German and back)
await t.go('/my/account');
await t.page.selectOption('#user_language', 'de');
await t.page.click('#my_account_form input[type=submit], input[name=commit]');
await t.settle();
await forge('xml');
const de = (await t.page.locator('#flash_error').textContent().catch(() => '')) || '';
if (!de.includes('Ungültiges LibreOffice-Konvertierungsformat')) t.problems.push(`German: "${de}"`);
await t.shot('refused-de', 'The same refusal for a German-speaking administrator: "Ungültiges LibreOffice-Konvertierungsformat; die Einstellungen wurden nicht gespeichert."', { full: false });
await t.go('/my/account');
await t.page.selectOption('#user_language', 'en');
await t.page.click('#my_account_form input[type=submit], input[name=commit]');
await t.settle();

// a valid format is still saved (and put back)
await t.go(URL);
await t.sudo();
await t.page.selectOption(SELECT, 'html');
await t.page.click('#settings form input[type=submit], form[action$="redmine_more_previews"] input[type=submit]');
await t.settle();
await t.sudo();
if (!(await t.page.locator('#flash_notice').count())) t.problems.push('valid format: no "Successful update"');
if ((await t.page.inputValue(SELECT)) !== 'html') t.problems.push('valid format: docx is not html after saving');
await t.shot('valid-saved', 'A format the file type offers (docx -> html) is saved as before', { full: false });
await t.page.selectOption(SELECT, 'pdf');
await t.page.click('#settings form input[type=submit], form[action$="redmine_more_previews"] input[type=submit]');
await t.settle();
await t.sudo();
await t.done();
