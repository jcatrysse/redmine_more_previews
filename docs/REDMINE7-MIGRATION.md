# Redmine 7 migration: redmine_more_previews

Start a Claude Code (or Codex) session on this repository, branch `redmine70-migration`, with:

> Read CLAUDE.md and docs/REDMINE7-MIGRATION.md, then carry out the Redmine 7 migration of this
> plugin as described there, on branch redmine70-migration. That includes the plugin's tests on
> PostgreSQL and MariaDB, every function exercised end to end on a real running Redmine in a
> browser (with and without permissions, failure paths included) with screenshots you looked at,
> and an OpenAI review of the diff when OPENAI_API_KEY is set. Report to me in Dutch at the end.

This file is the plan and the memory of that work. Update it as you go: verdicts, results,
what is left. Written 2026-10-06 from a measured analysis (report at the bottom).

## Status

| | |
|---|---|
| Plugin id | `redmine_more_previews` |
| GEOxyz runs today | `main` |
| Upstream | HugoHasenbein/redmine_more_previews main @ 0bca937b36c56e3114e582b9bdf3384814d394ca (2025-02-13, 5.0.9) |
| Runs on Redmine 7 as is | NEE (boot) |
| Runs on Redmine 7 after this branch | JA: tests and e2e green on PostgreSQL and MariaDB (see "Results") |
| Migration session | done 2026-10-06, branch head in `git log`; work list below all done or deferred with reason |
| Upstream sync | UPSTREAM DOOD: nothing upstream; fork already equals upstream 5.0.9 + 2 own commits; claude/redmine7-rails8-compat 4eb8dea cherry-picked |
| After sync | n.v.t. |
| Complexity (1 trivial .. 5 rewrite) | 3 |
| Measured on | Redmine 7.0.1 (7.0-stable-GEOxyz + latest 7.0-stable), Rails 8.1.3.1, Ruby 3.3.6, PostgreSQL 16 and MariaDB 10.11 |
| Branch head when this file was written | `70d635e` (plan), updated after the migration session |

## Already on this branch

- `e85347a` Remove `unloadable` from the vendored vince library (Rails 5.1)
- `010837c` Use File.exist? instead of File.exists? in RmpFile.directory
- `25b034c` Remove Redmine 7's markdownized preview cache in delete_from_disk!
- `82ebac6` Write zip entries without Zip::File#extract (rubyzip 3)

Added by the migration session (2026-10-06), one concern per commit, each with a test that fails
without it (checked by reverting the fix in the test checkout):

- `84eb934` test_setup.sh: create the PostgreSQL role when running as root (kit bug)
- `49d9d34` test suite (the plugin had none) and e2e seed; tests for the four commits above
- `65ac53a` locale keys that did not match English (pt-BR/pt/ru `label_debug`, cliff fr, nil_text pt, jp)
- `3de7f41` **SECURITY** asset path traversal: arbitrary file read for anyone who can see a previewable attachment
- `444c4b8` mark: textile previews (HTTP 500 before)
- `d4efca3` **SECURITY** stored XSS: sandbox CSP on previews, sanitized inline previews, cliff escaping, zippy folder names
- `81552a5` jQuery 3 `.on('load')` (JS error on every preview page)
- `93e9a16` SVG icons (`sprite_icon`, falls back on 5.1)
- `8558ef4` zippy: files in folders were double-encoded (empty download)
- `fb7060c` vince: no links to stylesheets Redmine no longer ships
- `20bdf3d` zippy/repository: archives in a repository previewed empty, their files not served
- `bf9e6a7` repository previews allowed with `browse_repository`, as init.rb intended
- `b04e121` preview URL without format: 404 instead of an octet-stream download
- `9088fd0` **SECURITY** repository preview cache keyed by repository id and revision (cross-project leak)
- `c19f76f` own review: sanitizer lists portable to Rails 6.1, revision memoized per request
- `700d486`, `38bc789` OpenAI review resolutions; workflow installs pandoc (and converters for e2e)
- `0725a43`, `07e502f`, `61efc98` e2e scenarios and screenshots (PostgreSQL, MariaDB, before on 5.1)
- `804b409` CodeQL workflow manual only

## Work list for the migration session

In this order: things that break, security, the GEOxyz changes, the open items, then the checks.

**Open items from the analysis** (Dutch; where they conflict with a decision or a priority item above, those win)

1. Review production converter settings per the overlap table (let core handle pdf/images/txt/md)
2. Not verified: peek/maggie pdf->png (no ghostscript in container), repository previews, tar/tgz
3. Pre-existing: $('#preview_frame').load(fn) removed in jQuery 3 -> JS error on every preview page; zippy links to files in subfolders double-encoded (%252F) -> empty download; vince view loads non-existent jquery-ui-1.11.0/tribute-3.7.3 CSS
4. Dead upstream plus three old gems from the same author (hbl_text, hash_base, deep_try)

**Verdicts (migration session)**

1. Converter settings in production: **deferred to the upgrade**, it is a production setting, not code.
   Listed under "After the upgrade"; the recommendation stands (core for pdf/images/txt/md; keep
   libre, cliff, zippy). Note: since `d4efca3` a `.html` preview through pass or mark is sandboxed,
   but core showing the source remains the safer default.
2. Verified now: peek pdf (PDF served, `%PDF`), maggie png->jpg (ImageMagick + Ghostscript
   installed), repository previews (md, docx, vcf, txt, zip, eml), tar and tgz (listing and files).
   Not verifiable here: the PDF *viewer* in the page (headless Chromium has none; the PDF is checked
   through its URL), maggie pdf->png (not activated: peek owns .pdf in the seed; same ImageMagick path
   as core thumbnails, which render on the issue page).
3. Done: `.on('load')` (`81552a5`), zippy encoding (`8558ef4`), vince CSS (`fb7060c`), icons
   (`93e9a16`). Found and fixed on the way: path traversal (`3de7f41`), stored XSS (`d4efca3`),
   repository cache leak (`9088fd0`), textile 500 (`444c4b8`), zip in repository (`20bdf3d`),
   browse_repository (`bf9e6a7`), locales (`65ac53a`).
4. Dead upstream and old gems: **deferred**, no Redmine 7 breakage. `hbl_text`, `hash_base`,
   `deep_try` install and load on Ruby 3.3 / Rails 8.1. A replacement is a product decision
   (open question 5).
5. Tests: see "Results". 5.1-stable also run (the security fixes are meant to go to production early).
6. Webhooks: **nothing to do.** The plugin does not change issue data or `issues/show.api.rsb`;
   it only renders previews of attachments and repository files. Webhook payloads are unaffected.
7. Every function by hand in a browser: see "Inventory" and "Results".

**Checks**

5. Run the plugin's whole test suite on Redmine 7.0-stable-GEOxyz with PostgreSQL AND MariaDB, and once on 5.1-stable if the branch is meant to stay 5.1-compatible.
6. Check Redmine 7 webhooks against this plugin (see "Rules"), and note the result here even if nothing is needed.
7. Verify every feature of the plugin by hand on a running Redmine 7 (screenshots).

## GEOxyz changes to review or re-apply

These GEOxyz commits are on the branch GEOxyz runs today and therefore on this branch. Review each one against the code it now sits on (upstream merges and Redmine 7 core): drop it if upstream or core now does the same, rewrite it if it is not up to the quality rules below (tests, I18n, security, portability), keep it otherwise. Record the verdict per commit in this file.

| commit | date | subject | verdict |
|---|---|---|---|
| `b564c08` | 2026-01-27 | Minor corrections in locales | **keep.** Renames `pt-br.yml` to `pt-BR.yml`; the key inside was already `pt-BR`, so no behaviour change. Covered by `test/unit/locales_test.rb`, which also found the real locale bugs fixed in `65ac53a`. |
| `db97351` | 2025-12-06 | Correct Gemfile for usage with bundler | **keep.** zippy no longer declares rubyzip; Redmine core pins it (`rubyzip ~> 3.4.0` on 7.0, also present on 5.1). Proven by bundle install on 5.1 and 7.0 and the zip tests (`test_zip_*`, `test_tgz_asset`). |

## Results (migration session, 2026-10-06)

### Baseline, before any change (Redmine 7.0.1 GEOxyz, PostgreSQL 16)

- Plugin tests: none existed ("This plugin has no tests").
- `./.codex/e2e.sh`: smoke 15 screenshots / 0 problems, core 6 / 0 (`docs/e2e/baseline/`).
  The smoke passed only because no converter was active; with converters on, the probes found the
  path traversal, the textile 500, the JS error on every preview page and the broken zip links.

### Plugin tests (`./.codex/test_plugin.sh`)

| Redmine | database | result |
|---|---|---|
| 7.0-stable-GEOxyz (7.0.1), Ruby 3.3.6, Rails 8.1.3.1, at `c19f76f` | PostgreSQL 16.15 | 46 runs, 375 assertions, 0 failures, 0 errors, 0 skips |
| 7.0-stable-GEOxyz, at `c19f76f` | MariaDB 10.11.14 | 46 runs, 375 assertions, 0 failures, 0 errors, 0 skips |
| 7.0-stable-GEOxyz + redmine_drawio, view_customize, redmine_wiki_extensions (redmine70-migration) | MariaDB 10.11 | 47 runs, 381 assertions, 0 failures, 0 errors, 0 skips (final test set, `38bc789`: + the Cc test from the review) |
| 7.0-stable-GEOxyz, final test set at `abdc217` | PostgreSQL 16.15 | 47 runs, 381 assertions, 0 failures, 0 errors, 0 skips |
| 5.1-stable, Ruby 3.2.6, at `c19f76f` | PostgreSQL 16 | 46 runs, 361 assertions, 0 failures, 0 errors, 0 skips |

Boot and production eager load: OK (the e2e server runs in production mode). Migrations: the plugin
has none.

### End to end (`./.codex/e2e.sh`, production mode, real browser)

| run | smoke | core | plugin scenarios | problems |
|---|---|---|---|---|
| PostgreSQL 16 (`docs/e2e/`) | 15 | 6 | 8 scripts, 46 screenshots | 0 |
| MariaDB 10.11 (`docs/e2e/mariadb/`) | 15 | 6 | 8 scripts, 46 screenshots | 0 |
| MariaDB + 3 other GEOxyz plugins (not committed) | 15 | 6 | 8 scripts, 46 screenshots | 0 |
| before: GEOxyz `main` on Redmine 5.1 (`docs/e2e/before/`) | - | - | 8 scripts | 65 problems, as expected: traversal LEAK, mail XSS ran, textile 500, JS errors, empty zip downloads |

Every screenshot was opened and looked at. One table per scenario with captions: `docs/e2e/<scenario>.md`.

### Inventory of functions

| function | how a user reaches it | scenario | screenshots (docs/e2e/) |
|---|---|---|---|
| Preview takeover of an attachment (module on, converter active) | click an attachment | converters, permissions | converters-sample-*.png |
| Libre: docx/odt/xlsx/csv... via LibreOffice (pdf, html, png) | attachment | converters | converters-sample-docx/odt/xlsx/csv |
| Cliff: eml, headers box, all header fields, Unsafe reload | attachment | mail | mail-headers, mail-unsafe-reload, mail-hostile |
| Vince: vcf business card | attachment, repository | converters, repository | converters-sample-vcf, repository-sample-vcf |
| Mark: md (html), textile (inline) via pandoc | attachment, repository | converters, repository | converters-sample-md/textile, repository-sample-md |
| Pass: html as is (sandboxed) | attachment | converters, security | converters-sample-html, security-sandbox |
| Teddie: txt | attachment, repository | converters, repository | converters-sample-txt, repository-sample-txt |
| Peek: pdf | attachment | converters | converters-sample-pdf |
| Maggie: png -> jpg | attachment | converters | converters-sample-png |
| Zippy: zip/tar/tgz listing, download of files (also in folders) | attachment, repository | archives, converters, repository | archives-*, repository-sample-zip |
| Nil Text (debug converter) | settings only (not for production, says its own warning) | settings | settings-double |
| Navigation between the attachments of a container | pagination under the preview | converters | converters-navigation-next |
| Update (reload) of a cached preview | "Update" link | converters | converters-reload |
| Repository entry preview + more_preview/more_asset routes | Repository > file | repository | repository-*.png |
| Plugin settings: embedding object/iframe, absolute URL, cache, debug, converters, formats, double type warning, help | Administration > Plugins > Configure | settings | settings-*.png |
| Project module "Redmine More Previews" | Project settings > Modules | permissions | permissions-module-off/on |
| Permission `use_redmine_more_previews` (public) | member roles | permissions | permissions-reporter |
| Converter checks on Administration > Information | Administration > Information | admin_info | admin_info-info |
| File type icons in attachment lists (CSS hook) | any attachment list | converters | converters-issue-attachments |
| Refusals: non-member on private project, anonymous, non-admin on settings and info | URL | permissions, settings, admin_info | *-refused, *-anonymous, permissions-outsider-page |
| Failure paths: traversal, no converter, unknown id, no format | URL | security (+ integration tests) | security-traversal-404 |
| REST API, mail in/out, rake, cron | the plugin has none | - | - |

### Reviews

- Own review of the whole diff `b564c08..HEAD`: two fixes in `c19f76f`.
- OpenAI review (gpt-5): `docs/reviews/openai-2026-10-06-c19f76f.md` (5 findings: 2 fixed, 3 not
  defects, with reasons) and a second pass `docs/reviews/openai-2026-10-06-700d486.md` (nothing new
  accepted). Every finding has a resolution.

### Not tested here (needs production or is out of reach)

- The PDF viewer inside the page (headless Chromium has no PDF plugin; the PDFs are checked through
  their URL: HTTP 200, `application/pdf`, `%PDF`). Check once in a real browser after the upgrade.
- Other repository types than git (Subversion, Mercurial): same code path (`Repository#entry`,
  `#cat`, `latest_changesets`), not exercised.
- The full set of GEOxyz plugins together: three that touch attachments/wiki/views were run
  together (above); the rest belongs in the coordinator's harness.
- Windows-specific branches of the converters.

## Decided by Jan (2026-10-07)

Answered by Jan on 2026-10-07 in the coordinating session (source: `docs/DECISIONS-2026-10-07.md`).
His choices and notes are quoted verbatim. Nothing is open for this plugin.

**General decisions, for every GEOxyz plugin**

- GEOxyz goes straight to Redmine 7: no backports to 5.1. Nothing is cherry-picked to the default
  branch or to the branch production runs today; `redmine70-migration` is what goes live with
  Redmine 7. Redmine 5.1 compatibility is no longer a requirement. -> Rules updated; the code paths
  this branch had added only for 5.1 are removed (see "Built for the decisions").
  *(This replaces former open question 1, "security fixes into production now": they go live with
  Redmine 7, not earlier.)*
- GEOxyz does not use MariaDB or MySQL; production runs PostgreSQL 16. Tests and e2e on PostgreSQL
  only; a MariaDB-only problem is a note, not a blocker. -> Rules updated. The MariaDB runs already
  made stay in "Results" as information.
- deface without a version constraint: **not applicable**, this plugin does not use deface.
- Core methods that other plugins also patch are patched with `prepend`, never `alias_method`. ->
  This plugin used `alias_method` to copy `find_attachment`, `read_authorize` and
  `find_project_repository` (not a chain, but it bypassed other plugins' prepends on those
  methods) and redefined `Attachment#delete_from_disk!` outright. Both changed (see below).
- GitHub Actions stay manual only: already so (`redmine-tests.yml`, `codeql-analysis.yml`).

**Decisions for this plugin**

| question | Jan's choice (verbatim) | what it means here |
|---|---|---|
| q1 Wachtwoorden en geheime sleutels uit de serverconfiguratie vervangen na de upgrade? | B: "Niet nodig, alleen vertrouwde gebruikers" (Geen werk, maar alleen verantwoord als geen onbetrouwbare gebruiker ooit een previewbare bijlage kon openen.) | Recorded only: no rotation step after the upgrade. The traversal fix itself (`3de7f41`) goes live with Redmine 7. |
| q2 Voorbeeldweergaven blijven in een afgeschermde omgeving (zandbak) draaien? | A: "Zandbak houden" (De beste bescherming tegen een vijandig HTML-bestand of mail; de vCard toont een ander lettertype.) | Kept as built in `d4efca3`. |
| q3 Welke bestandstypes laat je na de upgrade door Redmine zelf tonen in plaats van door de plugin? | A: "Advies volgen" (Redmine toont pdf, beelden, tekst en md, de plugin houdt Office, mail en zip, en de converters pass en mark-html gaan uit.) | Built as a rake task that switches exactly those types off in the plugin settings, run once after the upgrade (see "After the upgrade"). |
| q4 Wat doen we met de verlaten upstream en de drie oude bibliotheken van deze plugin? | A: "Houden voor de upgrade, daarna beslissen" (Geen werk nu; de niet-onderhouden code blijft voorlopig in gebruik.) | Recorded; no change. To decide after the upgrade. |
| q5 De nutteloze CodeQL-controle in de repository nu verwijderen of later? | A: "Op handmatig laten, later verwijderen" (Geen werk nu; het bestand blijft voorlopig staan.) | Kept manual (`804b409`); delete later. |

Former open questions 3 (inline previews sanitized) and 6 (previews with `browse_repository`
alone) were not put to Jan separately; they stay as built and recorded in "Already on this branch".

## After the upgrade (production)

Actions the person doing the upgrade must take, or know about, for this plugin:

- Review the converter settings: let core handle pdf, images, txt and md; keep libre/cliff/zippy. Install LibreOffice and Ghostscript on the server if kept; core needs Pandoc for its own Office preview.
- Empty the preview cache once after deploying: `rm -rf <redmine>/tmp/more_previews/*`. Cached zip
  tables from before still carry the double-encoded links, and repository previews moved to a new
  layout (by repository id and revision; the old directories are never read again).
- The mark converter (md/textile) needs `pandoc` on the server, zippy nothing, maggie ImageMagick,
  maggie/peek pdf->image Ghostscript, libre LibreOffice (`soffice`). Administration > Information
  lists each check.
- The plugin writes to `public/plugin_assets/redmine_more_previews/converters` at boot (converter
  logos and icons); that directory must be writable for the Redmine user, as on 5.1.
- Check once in a real browser that a PDF preview (peek, or libre to pdf) shows in the page.
- No rotation of passwords or secret keys after the upgrade (Jan, 2026-10-07, q1: "Niet nodig, alleen
  vertrouwde gebruikers").

## How to test

```sh
./.codex/redmine_clone.sh 7.0-stable-GEOxyz      # or 5.1-stable / 6.1-stable / 7.0-stable
./.codex/test_setup.sh                                 # RMP_DB=mariadb for MariaDB, RMP_PROVISION_DB=0 if a server runs
./.codex/test_plugin.sh                                # minitest + rspec of this plugin
```

```sh
./.codex/start_server.sh       # real Redmine (production mode) with this plugin, seeded users and projects
./.codex/e2e.sh                # browser: smoke over the plugin's pages, core issue flows, test/e2e/*.mjs
./.codex/openai_review.sh      # independent OpenAI review of the diff, only when OPENAI_API_KEY is set
```
Write one scenario per function in `test/e2e/<function>.mjs` (example at the top of
`.codex/e2e/lib.mjs`); screenshots and a table per scenario land in `docs/e2e/`. Users:
`admin`, `manager` (every permission), `reporter` (no plugin permissions), `outsider` (no
membership); password `Redmine7Test!`. Needs Node with Playwright and Chromium
(`npm install -g playwright && npx playwright install --with-deps chromium`).

On GitHub the same runs by hand only: Actions > "Redmine tests (manual)" > Run workflow (tick
"e2e" for the browser run; screenshots come back as an artifact).

The coordinator's harness (`plugin-check.sh` in the migration kit, kept outside this repo) adds a
browser smoke test of every page the plugin adds and runs all GEOxyz plugins together; the
results quoted in the analysis come from it.

## How the migration session works (same for every plugin)

1. **Start**: `git fetch && git checkout redmine70-migration && git pull`. Read this whole file,
   including the analysis report at the bottom. Do not reopen decisions recorded here.
2. **Baseline, before you change anything**:
   - the plugin's tests on Redmine 7.0-stable-GEOxyz with PostgreSQL and with MariaDB;
   - a real running Redmine with this plugin (`./.codex/start_server.sh`) and the browser run
     (`./.codex/e2e.sh`: smoke over every page the plugin adds, plus the core issue flows).
   Write the numbers here. Something already broken now is a finding, not your regression.
3. **Inventory of functions**: list every function of the plugin in this file, in a table
   "function | how a user reaches it | scenario | screenshot". Take them from the README,
   `init.rb` (permissions, menus, settings, project modules), routes, hooks and view
   overrides, macros, mail handling, API endpoints, rake tasks and cron jobs. This table is the
   coverage list for step 8; a function that is not in it will not be tested.
4. **GEOxyz changes**: go through the table above, one item at a time. Each kept or re-made change
   is its own commit with a test that proves it. Record the verdict in the table.
5. **Work list**: then the numbered list, in order. One concern per commit.
6. **Portability**: everything must run on Redmine's supported databases (PostgreSQL,
   MySQL/MariaDB; SQLite where the plugin already supports it). Migrations must be reversible and
   are run down and up on PostgreSQL and MariaDB.
7. **Together**: run with the other GEOxyz plugins installed (the migration kit's harness, or
   `RMP_EXTRA_PLUGINS`). A failure that only appears in combination is a finding to record here.
8. **End to end, visually, every function**: on the real Redmine from `start_server.sh`
   (production mode, the way GEOxyz runs it), write one scenario per function in
   `test/e2e/<function>.mjs` with `.codex/e2e/lib.mjs` and run them with `./.codex/e2e.sh`.
   - Each function as the users that matter: `admin`, `manager` (every permission, the
     plugin's included), `reporter` (member without the plugin's permissions), `outsider`
     (no membership, private project must stay invisible).
   - The failure paths too: setting off, permission absent, empty state, invalid input, the
     value that used to raise. A refusal that is shown is evidence as much as a success.
   - One screenshot per function and per path, with a caption saying what it proves. Open
     every screenshot and look at it: a picture nobody looked at proves nothing. Commit them
     in `docs/e2e/` and list them in the inventory table.
   - Functions without a page (mail in and out, REST API, rake tasks, cron, webhooks): exercise
     them against the same running instance (mails land in `redmine/tmp/mails`, `t.mails()`
     reads them; API through `t.page.request`) and record command and result.
   - Before pictures where behaviour or layout changes: the branch GEOxyz runs today, on
     Redmine 5.1, same scenarios, `RMP_E2E_OUT=docs/e2e/before`.
   - Run the whole e2e set once on MariaDB as well (`RMP_DB=mariadb`, then `start_server.sh --reset`).
9. **Independent review**: first your own, adversarial: re-read the whole diff as if someone
   else wrote it and you are paid to reject it. Then, **when `OPENAI_API_KEY` is set in the
   session**, `./.codex/openai_review.sh`: it sends the diff of this branch to an OpenAI model
   and writes `docs/reviews/openai-<date>-<sha>.md`. Every finding gets a `Resolution:` line
   there (fixed in <commit>, with a test, or why not). Fix, re-run the tests and the e2e set,
   and run the review again until it has nothing new that you accept. Without the key: write
   "OpenAI review: skipped, no OPENAI_API_KEY" in the report; never send code anywhere else.
10. **After the upgrade**: anything the production upgrade must do for this plugin (data fixes,
    settings, cron, files, removed features) goes into the section "After the upgrade".
11. **Finish**: update "Status", the inventory and the work list in this file, push
    `redmine70-migration`, and report: what changed, test numbers on both databases, e2e
    numbers (scenarios, screenshots, problems), the review result, what is left, what needs Jan.

### Stop and ask Jan when
- a GEOxyz change would be lost or behave differently for users;
- a new gem, a new setting with user impact, or a schema change not required by Redmine 7 seems needed;
- the change would send data to an external service (the OpenAI review of the code diff is the
  one exception Jan approved, and only when the key is present);
- upstream and GEOxyz disagree on behaviour and both are defensible.

## Rules

- **Target**: Redmine 7.0-stable-GEOxyz (https://github.com/jcatrysse/redmine), Rails 8.1, Ruby 3.3+.
  Core sources for comparison: branches `5.1-stable`, `6.1-stable`, `7.0-stable`, `7.0-stable-GEOxyz`.
- **Evidence**: never report a test, lint, browser check or review as passed without having seen
  it. Quote the summary lines; list the screenshots. "Should work" is not a result, and a green
  test suite is not proof that a feature works in the browser.
- **Tests**: never skip, delete or weaken a test. A test that encodes Redmine 5 markup or
  behaviour is updated to Redmine 7, with the reason in the commit. Every fix gets a test that
  fails without it.
- **Minimal diffs** in the plugin's own style. No reformatting, no unrelated refactoring.
  Something wrong elsewhere: write it down here, do not fix it in passing.
- **Security**: authorization on every action and entry point; `safe_attributes`, never
  `to_unsafe_hash` into `update`; no SQL built from params; no secrets in logs; no `html_safe` on
  user input.
- **Webhooks (new in Redmine 7)**: core sends issue payloads (core `issues/show.api.rsb`, rendered
  as the webhook owner) to webhook endpoints, past plugin hooks and controller patches. If the
  plugin hides, adds or changes issue data, make webhooks consistent with that or record why not.
- **Redmine 7 conventions**: SVG icons through `sprite_icon` (the `icon icon-*` CSS is gone),
  Propshaft assets under `assets/` (`/assets/plugin_assets/<id>/...`), the new header and user menu,
  `ContextMenus::*Controller`, Loofah-based text formatting, Chart.js as an ES module, sudo mode
  (on by default: `t.sudo()` in a scenario). The breaker list is in the migration kit's CHECKLIST.md.
- **Locales**: keep the locales the plugin ships in sync; translate a new key by matching the
  closest existing key in the same file, not from scratch; do not add new languages.
- **No 5.1** (Jan, 2026-10-07): Redmine 5.1 compatibility is no longer required; do not add code
  paths that exist only for 5.1.
- **PostgreSQL only** (Jan, 2026-10-07): production runs PostgreSQL 16; tests and e2e run there.
  Keep SQL portable where it costs nothing; a MariaDB-only problem is a note, not a blocker.
- **prepend, never alias_method** (Jan, 2026-10-07) on a core method other plugins also patch.
- (former) **5.1 compatibility**: prefer fixes that also run on Redmine 5.1 so they can be merged early;
  say so when a fix cannot.
- **Git**: work on `redmine70-migration` only; never push to the default branch; never force-push
  a branch someone else uses. Descriptive commit messages (what and why). Push after every
  commit, together with the updated status in this file: a cloud session can stop at a usage
  limit, and work that is not pushed is lost with its container.
- **GitHub Actions**: manual only (`workflow_dispatch`). Do not add push, pull_request or schedule
  triggers.

## Definition of done

- All items of the work list are done or explicitly deferred with a reason, in this file.
- The plugin's tests are green on Redmine 7.0-stable-GEOxyz with PostgreSQL (MariaDB no longer required, 2026-10-07)
  (numbers in this file); boot, production-like eager load, migrations up/down OK.
- Every function in the inventory exercised end to end on a real running Redmine, with and
  without permissions and on its failure paths; `./.codex/e2e.sh` green; screenshots looked at,
  committed in `docs/e2e/` and listed.
- Review done: your own, and the OpenAI review when the key is present, every finding resolved
  in `docs/reviews/`.
- No new failure when run together with the other GEOxyz plugins.
- "After the upgrade" lists every action production needs; "Status" is current.


## Analysis report (2026-10-06, Dutch)

# redmine_more_previews
- Gebruikte branch: main @ b564c08 (2026-01-27) - plugin id redmine_more_previews, versie 5.0.9
- Upstream: HugoHasenbein/redmine_more_previews - upstream HEAD main @ 0bca937 (2025-02-13, "5.0.9", "runs on Redmine 6.x")
- Fork t.o.v. upstream: 2 eigen commits (db97351 Gemfile voor bundler, b564c08 locales), 0 upstream-commits ontbreken.
- Andere relevante branches: fork `claude/redmine7-rails8-compat` (4eb8dea: `unloadable` in vince uitgecommentarieerd), hergebruikt via cherry-pick. Upstream `debug` (2021, oud). Geen onderhouden fork gevonden.
- Opbouw: 10 converters (cliff eml, libre office->pdf/html/png via soffice, maggie beelden/pdf via ImageMagick, mark md/textile/html, nil_text/teddie txt, pass html, peek pdf, vince vcf, zippy zip/tar/tgz). Prepend op `AttachmentsController#show` en `RepositoriesController#entry`. Patches op Attachment, Repository, Entry, MimeType, AdminController#info en ApplicationHelper. Plugin-Gemfile: `marcel` + converter-Gemfiles (`hbl_text`, `hash_base`, `deep_try`, `zlib`). Geen migraties of tests.

## 1. Werkt out of the box op Redmine 7?   NEE
- `FAIL boot`: `converters/vince/lib/vince_lib/v_object/constants/defaults.rb:29` `unloadable` -> NameError (Rails 5.1+), in 10 vince-bestanden. De commitboodschap van 4eb8dea zegt dat het pas bij de eerste preview faalt; gemeten faalt de **boot**. (`results/1006-085441-s1-redmine_more_previews_origin_main`)

## 2. Upstream sync?   UPSTREAM DOOD
- Upstream main = 5.0.9, zelfde code als de fork. Geen R7-werk upstream.

## 3. Werkt na sync op Redmine 7?   n.v.t.

## 4. Complexiteit en blokkers   score 3
- Blokkers (gefixt):
  - vince `unloadable` -> cherry-pick van 4eb8dea (e85347a).
  - `lib/redmine_more_previews/lib/rmp_file.rb:151` `File.exists?` (Ruby 3.2 verwijderd) -> 010837c. Momenteel geen aanroeper, maar publieke helper.
  - `converters/zippy/lib/zippy.rb:209` `zip_file.extract(entry, tmpasset)`: rubyzip 3.4 (R7) interpreteert het pad relatief t.o.v. `destination_directory` ('.'). Gemeten: `ENOENT .../slots/s1/tmp/d2026.../top.txt`, downloaden van een bestand uit een zip-preview faalt. -> 82ebac6 (stream naar bestand schrijven, zoals de tar-tak al doet). Na de fix gemeten: `?asset=top.txt` -> 200 "top level".
  - `lib/redmine_more_previews/patches/attachment_patch.rb:170` vervangt `Attachment#delete_from_disk!` door een eigen kopie. R7 voegde daar het verwijderen van de pandoc-preview-cache toe. Gemeten vóór de fix: na `destroy` van een docx bleef het `.md`-cachebestand staan, ná de fix weg. -> 25b034c.
- Functioneel gemeten op R7 (converters geactiveerd via de instellingen, module aan): libre docx->pdf 200 `application/pdf` 19 KB, libre odt->html 200, vince vcf->html, cliff eml->html, mark md->html, zippy zip-lijst (met mappen) en download van een bestand op het hoogste niveau. Instellingenpagina laadt (87 checkboxes, alle converters zichtbaar). `/admin/info` (patch) OK in smoke.
- Niet geverifieerd: peek/maggie pdf->png (ghostscript ontbreekt in de container, `Redmine::Thumbnail` slaat pdf dan over; API ongewijzigd t.o.v. 5.1), repository-previews (`RepositoriesController#entry`), tar/tgz.
- Bestaande fouten (al op 5.1, niet gefixt):
  - `app/views/attachments/more_preview.html.erb:53` en `repositories/more_preview.html.erb:63` `$('#preview_frame').load(fn)`, verwijderd in jQuery 3 -> JS-fout "e.indexOf is not a function" op elke previewpagina (alleen de ajax-indicator).
  - zippy-links naar bestanden in submappen zijn dubbel ge-encodeerd (`inner%252Fhello.txt`) -> lege download.
  - `converters/vince/app/views/vince/vince.html.erb:2` laadt `jquery-ui-1.11.0`/`tribute-3.7.3` CSS -> 404.
  - `icon icon-reload/-help/-warning` in views -> iconen weg (#43206), cosmetisch.
- Overlap / botsing met Redmine 7 core: geen crash. De plugin wint per bestandstype zolang de projectmodule aan staat en de converter voor die extensie actief is (`AttachmentsController#show`-prepend gaat vóór core). Gemeten: met peek actief vervangt de plugin de PDF-viewer van core. Met de module uit toont R7 de pandoc-markdownpreview (docx) en `<object type="application/pdf">` (pdf).

  | Bestandstype | Redmine 7 core | Plugin-converter | Advies |
  |---|---|---|---|
  | pdf | inline viewer (#22483) | peek, maggie | core: peek/maggie-pdf uit |
  | png/jpg/gif/bmp/webp/avif/svg | image-preview (+ SVG #44126, AVIF) | maggie | core: maggie uit |
  | txt / code | tekst met syntax-highlighting | nil_text, teddie | core: uit |
  | md / textile | markdown/textile-weergave | mark | core: mark-md/textile uit |
  | docx, odt (+ xlsx/pptx bij pandoc >= 3.8.3) | pandoc -> markdown, alleen tekst | libre (layout-getrouw pdf/html/png) | plugin houden als de layout telt |
  | doc, xls, ppt, rtf, ods, odp, fod*, csv-tabel | niet (csv als tekst) | libre | plugin |
  | eml / mime | niet | cliff | plugin |
  | zip / tar / tgz | niet | zippy | plugin |
  | vcf | als tekst | vince | plugin (optioneel) |
  | html | broncode als tekst | mark, pass | plugin alleen als HTML-rendering gewenst is (XSS-afweging) |
- Open werk voor ansif:
  1. Converterinstellingen in productie herzien volgens de tabel (dubbele typen naar core laten gaan).
  2. Testen met ghostscript (pdf->png) en een repository-preview.
  3. `.load(fn)` -> `.on('load', fn)` en de dubbele encoding in zippy (bestaande bugs).
  4. De plugin hangt van een dode upstream en drie oude gems van dezelfde auteur af (`hbl_text`, `hash_base`, `deep_try`); op termijn de libre/cliff/zippy-functies apart houden of vervangen.

## Branch redmine70-migration
- Basis: origin/main @ b564c08
- Commits: e85347a Remove `unloadable` from the vendored vince library (Rails 5.1) (cherry-pick 4eb8dea) · 010837c Use File.exist? instead of File.exists? in RmpFile.directory · 25b034c Remove Redmine 7's markdownized preview cache in delete_from_disk! · 82ebac6 Write zip entries without Zip::File#extract (rubyzip 3)
- Eindresultaat harness (`results/1006-095537-s1-redmine_more_previews_redmine70-migration`): boot OK, eager OK, migraties OK, smoke 66/66 (6 plugin-routes, INFO 404 = voorbeeld-id's)
- Rollback migraties: n.v.t. (geen migraties)

