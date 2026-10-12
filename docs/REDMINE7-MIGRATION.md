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
| Runs on Redmine 7 after this branch | JA: tests and e2e green on PostgreSQL 16 (see "Results"); also with the other GEOxyz plugins, apart from their own defects listed there |
| Migration session | done 2026-10-06; Jan's decisions of 2026-10-07, round 4 (2026-10-11) and round 5 (2026-10-12, security fixes of curecodejp 6.1.2: conversion limits, Vince) built (see "Decided by Jan") |
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
| 7.0-stable-GEOxyz, after Jan's decisions (`8d521d5`) | PostgreSQL 16.15 | 56 runs, 422 assertions, 0 failures, 0 errors, 0 skips |
| same, with 37 other GEOxyz plugins (all `redmine70-migration`: 30 public, 7 private) | PostgreSQL 16.15 | 56 runs, 422 assertions, 0 failures, 0 errors, 0 skips |
| 7.0-stable-GEOxyz, after round 4 (`5f38162`) | PostgreSQL 16.15 | 62 runs, 466 assertions, 0 failures, 0 errors, 0 skips |
| same, with the 37 other GEOxyz plugins (heads of 2026-10-11) | PostgreSQL 16.15 | 62 runs, 466 assertions, 0 failures, 0 errors, 0 skips |
| 7.0-stable-GEOxyz, after round 5 (`3c25209`) | PostgreSQL 16.15 | 252 runs, 1457 assertions, 0 failures, 0 errors, 0 skips |
| same, with the 37 other GEOxyz plugins (heads of 2026-10-12) | PostgreSQL 16.15 | 252 runs, 1457 assertions, 0 failures, 0 errors, 0 skips |
| (former, 5.1 no longer required) 5.1-stable, Ruby 3.2.6, at `c19f76f` | PostgreSQL 16 | 46 runs, 361 assertions, 0 failures, 0 errors, 0 skips |

Boot and production eager load: OK (the e2e server runs in production mode). Migrations: the plugin
has none.

### End to end (`./.codex/e2e.sh`, production mode, real browser)

| run | smoke | core | plugin scenarios | problems |
|---|---|---|---|---|
| PostgreSQL 16 (`docs/e2e/`) | 15 | 6 | 8 scripts, 46 screenshots | 0 |
| MariaDB 10.11 (`docs/e2e/mariadb/`) | 15 | 6 | 8 scripts, 46 screenshots | 0 |
| MariaDB + 3 other GEOxyz plugins (not committed) | 15 | 6 | 8 scripts, 46 screenshots | 0 |
| PostgreSQL 16 after Jan's decisions (`docs/e2e/`, replaces the run above) | 15 | 6 | 9 scripts, 62 screenshots | 0 |
| PostgreSQL 16 after round 5 (`docs/e2e/`, current) | 15 | 6 | 13 scripts, 89 screenshots (helpdesk_mail checks nothing without the helpdesk) | 0 |
| PostgreSQL 16 with all 37 other GEOxyz plugins, round 5 (`docs/e2e/combined/`, current) | 16 | 6 | 13 scripts, 93 screenshots | 1, not from this plugin (redmine_view_issue_description's 403) |
| PostgreSQL 16 after round 4 | 15 | 6 | 11 scripts, 77 screenshots | 0 |
| PostgreSQL 16 with all 37 other GEOxyz plugins, round 4 | 16 | 6 | 11 scripts, 77 screenshots | 1, not from this plugin (redmine_view_issue_description's 403) |
| (2026-10-07) PostgreSQL 16 with 36 other GEOxyz plugins | 16 | 6 | 9 scripts, 61 screenshots | 4, none from this plugin (below) |
| before: GEOxyz `main` on Redmine 5.1 (`docs/e2e/before/`) | - | - | 8 scripts | 65 problems, as expected: traversal LEAK, mail XSS ran, textile 500, JS errors, empty zip downloads |

Every screenshot was opened and looked at.

**With all GEOxyz plugins (2026-10-11)**: the server boots with all 37 and Project > Settings
answers 200; the defects of 2026-10-07 below are fixed in those plugins' branches. Left: the
403 of `redmine_view_issue_description` (by design).

**With all GEOxyz plugins (2026-10-07)**, problems that belonged to other plugins (for their own
migration sessions; this plugin's scenarios pass there):
- `redmine_issue_field_visibility` chains `IssueQuery#initialize_available_filters` with
  `alias_method` while `redmine_agile` prepends it: `SystemStackError`, the server does not boot
  (`rake redmine:load_default_data` aborts). The combined e2e run leaves
  `redmine_issue_field_visibility` out; the combined plugin tests ran with it.
- Project > Settings answers HTTP 500: `redmine_mail_digest` chains `project_settings_tabs` with
  `alias_method` (`project_settings_tabs_with_issue_digest`) among a dozen plugins that prepend it
  ("super: no superclass method"). Seen in `combined/smoke-06.png` and
  `combined/permissions-module-settings-error.png`; the module switch of the permissions scenario
  cannot run there.
- `/issues/1` as `reporter` answers 403: `redmine_view_issue_description` requires its own
  permission, which the seed's Reporter role lacks; by design of that plugin.
- The issue JSON API returns no body for a logged-in session with all plugins installed; the
  scenarios now use the API key. One table per scenario with captions: `docs/e2e/<scenario>.md`.

### Inventory of functions

| function | how a user reaches it | scenario | screenshots (docs/e2e/) |
|---|---|---|---|
| Preview takeover of an attachment (module on, converter active) | click an attachment | converters, permissions | converters-sample-*.png |
| Libre: docx/odt/xlsx/csv... via LibreOffice (pdf, html, png) | attachment | converters | converters-sample-docx/odt/xlsx/csv |
| Cliff: eml, headers box, all header fields, Unsafe reload (administrators only) | attachment | mail | mail-headers, mail-unsafe-reload, mail-hostile |
| Vince: vcf business card | attachment, repository | converters, repository | converters-sample-vcf, repository-sample-vcf |
| Mark: md (html), textile (inline) via pandoc | attachment, repository | converters, repository | converters-sample-md/textile, repository-sample-md |
| Pass: html as is (sandboxed) | attachment | converters, security | converters-sample-html, security-sandbox |
| Teddie: txt | attachment, repository | converters, repository | converters-sample-txt, repository-sample-txt |
| Peek: pdf | attachment | converters | converters-sample-pdf |
| Maggie: png -> jpg | attachment | converters | converters-sample-png |
| Zippy: zip/tar/tgz listing, download of files (also in folders) | attachment, repository | archives, converters, repository | archives-*, repository-sample-zip |
| Nil Text (debug converter) | settings only (not for production, says its own warning) | settings | settings-double |
| Navigation between the attachments of a container | pagination under the preview | converters | converters-navigation-next |
| Update (reload) of a cached preview, administrators only since round 5 | "Update" link | converters, limits | converters-reload, limits-reload-users, limits-links-admin/manager |
| Repository entry preview + more_preview/more_asset routes | Repository > file | repository | repository-*.png |
| Plugin settings: embedding object/iframe, absolute URL, cache, debug, converters, formats, double type warning, help | Administration > Plugins > Configure | settings | settings-*.png |
| Project module "Redmine More Previews" | Project settings > Modules | permissions | permissions-module-off/on |
| Permission `use_redmine_more_previews` (public) | member roles | permissions | permissions-reporter |
| Repository previews and assets need "Browse repository" (round 4) | repository file as viewer / reporter / outsider / anonymous | repository_permissions | repository_permissions-*.png |
| Maggie refuses a disguised PDF, converts real PDF and PNG (round 4) | attachment preview with Maggie on | maggie | maggie-*.png |
| Hand-over of pdf, images, txt, md, textile, html to Redmine (rake task, Jan q3) | `rake redmine_more_previews:use_core_previews` once after the upgrade | core_handover | core_handover-*.png |
| Converter checks on Administration > Information | Administration > Information | admin_info | admin_info-info |
| File type icons in attachment lists (CSS hook) | any attachment list | converters | converters-issue-attachments |
| Refusals: non-member on private project, anonymous, non-admin on settings and info | URL | permissions, settings, admin_info | *-refused, *-anonymous, permissions-outsider-page |
| Failure paths: traversal, no converter, unknown id, no format | URL | security (+ integration tests) | security-traversal-404 |
| Conversion limits on the settings page (round 5; Cliff and Zippy limits in their own boxes) | Administration > Plugins > Configure | limits | limits-settings |
| Archive bomb and zip of too many entries refused (413) | attachment preview / asset | limits | limits-bomb-listing, limits-archives-413, limits-many-page |
| Email too large, too deeply nested, of too many parts: refused with the reason | attachment | limits | limits-emails-refused, limits-nested-page |
| A converter program that hangs: stopped at the time limit with its process group, failure remembered | attachment preview | limits | limits-hang |
| Cache clean rake task `redmine_more_previews:cache:clean DAYS=30` | cron, see "After the upgrade" | limits | limits-cache-clean |
| Hostile vCard: name as text, no javascript: links, no GEO map link from an injected value, no file: photo | attachment | limits | limits-hostile-vcard |
| Hostile customer email as message.eml on a helpdesk ticket (combined run with redmine_contacts_helpdesk) | helpdesk ticket attachment | helpdesk_mail | combined/helpdesk_mail-*.png |
| REST API, mail in/out | the plugin has none | - | - |

### Reviews

- Own review of the whole diff `b564c08..HEAD`: two fixes in `c19f76f`.
- OpenAI review (gpt-5): `docs/reviews/openai-2026-10-06-c19f76f.md` (5 findings: 2 fixed, 3 not
  defects, with reasons) and a second pass `docs/reviews/openai-2026-10-06-700d486.md` (nothing new
  accepted). Every finding has a resolution.

- Round 5 (2026-10-12): own review by an independent reviewer of `7e7886a..HEAD` (13 findings: 10
  fixed or mitigated with tests in `1635550`, `5f02e97`, `3c25209`; the rest recorded with reasons under "Round 5"
  above) and OpenAI review (gpt-5) `docs/reviews/openai-2026-10-12-d78c880.md` (4 findings: 1 fixed,
  3 not defects, with reasons).

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

**Built for the decisions (2026-10-07)**, one commit each, with a test that fails without it:

| decision | commit | test |
|---|---|---|
| recorded in this plan, rules updated | `7a9cfb9` | - |
| prepend instead of alias_method | `5b627bf`: controller filters called through lambdas instead of `alias_method` copies; `Attachment#delete_from_disk!` a prepended module calling `super`; `Redmine::MimeType.css_class_of` prepended | `test/unit/patches_test.rb`, `test_more_preview_runs_core_filters_through_other_plugins_prepends` |
| no 5.1 code paths | `5a472e3`: `sprite_icon` directly, no version branches in the tests | removal only; `test_preview_page_icons` and the destroy tests cover the behaviour (no test can fail on a removed fallback) |
| q3 core previews pdf, images, text, md | `8d521d5`: `rake redmine_more_previews:use_core_previews` (`DRY_RUN=1`), run once after the upgrade | `test/unit/core_handover_test.rb` (incl. the rake task), `test_after_the_hand_over_core_previews_pdf_and_the_plugin_keeps_office`, e2e `core_handover` |
| q1, q2, q4, q5 | recorded only | - |

**Round 4, 2026-10-11: security fixes of curecodejp/redmine_more_previews v6.1.1** (Jan's decision
in `docs/DECISIONS-2026-10-07.md`, section "Round 4"; ported by hand, the upstream commit named
in each commit):

| upstream fix | Jan | here | test |
|---|---|---|---|
| 97f33d5 repository previews need `browse_repository` | port | `afe995a`: init.rb registers `repositories/more_preview` and `more_asset` under `browse_repository` only (view_changesets covers revisions, not file content) | `test_more_preview_and_asset_are_refused_with_view_changesets_alone` (200 with the file before); e2e `repository_permissions` |
| e58d928 Maggie only hands files to ImageMagick as their own type | port, Maggie part | `5f38162`: PDF must pass `Redmine::Thumbnail.valid_pdf_magic?`; inputs with their coder (`jpeg:`, `png:`, `gif:`, `bmp:`, `pdf:`); fixed output `out.<format>`; `-limit` before the input | `test/unit/maggie_test.rb`, `test_maggie_still_converts_a_png_and_a_pdf`; e2e `maggie` |
| ad8db89 Peek checks the PDF | not ported | Peek uses `Redmine::Thumbnail.generate`, which checks the start of a PDF on Redmine 7 | - |
| a3b07ae, 762bf11 repository cache per repository and content | not ported, recorded | already closed by `9088fd0` (repository id + revision the entry last changed in) | see below |
| Zippy `rev` parameter, Redmine 6 icon CSS | seen, not needed | the repository links are built from the request (`20bdf3d`); icons are `sprite_icon` | - |

Known limitations, not defects (recorded with Jan's round-4 decision): a repository without
revisions (Filesystem) or without fetched changesets can keep a stale preview, because the cache key
then falls back to the requested revision; the 5.1 cache below `repository/` stays on disk, unread
(removed once after the upgrade, see there). Maggie without Ghostscript copies a valid PDF under the
image name (pre-existing, upstream does the same; the response is sandboxed): GEOxyz installs
Ghostscript, and Maggie is off after the hand-over task.

**Round 5, 2026-10-12: security fixes of curecodejp/redmine_more_previews v6.1.2** (Jan's decision in
`docs/DECISIONS-2026-10-07.md`, section "Round 5"; ported by hand in upstream's order, the upstream
commits named in each commit, upstream's tests ported where they fit):

| part | here | tests (each fails without its change) |
|---|---|---|
| time limit for every converter command, whole process group stopped (TERM, then KILL), Libre at least 120 s | `d0b3d71` (RmpProcess.run, Conversion#command with one deadline per conversion) | rmp_process_test (Windows skips removed, zombies of a container without init counted as stopped), conversion_timeout_test |
| at most `max_conversions` at once over all processes (flock slots), bounded waits, 503 with Retry-After beyond | `cf54a80` | preview_busy_test, conversion_limits_test |
| Peek's PDF images through the plugin's `convert` with Maggie's `-limit`s and the `pdf:` coder | `0f5d262` | peek_test |
| the limits as plugin settings, described on the settings page; a missing or non-positive value falls back to the default | `28029fd` (+ later parts) | plugin_settings_limits_test |
| Cliff: size (50 MiB), parts (1,000), attachments listed (1,000), names in a loop | `0601757` | cliff_limits_test |
| repository files (50 MiB, unknown size refused), Zippy (10,000 entries, 1 GiB unpacked, 100 MiB per entry, 1 GiB stored per archive, 64 levels), previews (100 MiB), cache (10 GiB); 413 | `8098c19`: Zippy rebuilt on upstream's walk with our repository link routing; the zip entry count follows **rubyzip 3.4** (Redmine 7), not 2.4 as upstream | zippy_limits_test (zip64 cases adapted), preview_busy_test, conversion_limits_test |
| failures remembered (10 min, `failure_ttl`), reload/unsafe for administrators only, links hidden for others | `da37223`, `74f59fc` (inline previews, the preview's own name as asset, normalized asset names) | preview_reload_failures_test, attachment_previews_test |
| rake task `redmine_more_previews:cache:clean DAYS=30` | `72a3a9e`, in our rake file next to `use_core_previews` | cache_clean_test (+ the task itself) |
| Cliff parses in a forked child (time limit, 1 GiB address space, resident memory watched), delimiters counted after any line break, nesting and parsed bodies bounded on Mail's parts, long mbox "From " line refused | `0087565` | cliff_limits_test, rmp_process_test (the lone CR test no longer asserts that Mail splits there: Mail 2.9 does not) |
| Zippy assets from the stored list, failures per preview and asset | `dcc28a5`; rubyzip 3's `EntrySizeError.new(entry)`; the pages no longer forward an `asset` parameter to the frame | attachments_more_asset_test (frame is an `<object>` with embedding 0) |
| why an email is not previewed, without backtrace or message; the refusal reasons translated (upstream: English only) | `f448b14` | cliff_limits_test, cliff_body_test |
| Vince: name escaped, URI links only for http(s), ftp, mailto, tel, geo (IMPP also xmpp, sip(s), im, skype), GEO only with valid coordinates; PHOTO/LOGO `file:` branch removed (024bd62, 6.1.0) | `6706d5a` | vince_uri_link_test, vince_uri_image_test, vince_html_template_test (FN only) |

Found while sweeping all upstream commits since 5.0.9 for security fixes beyond the two parts Jan named:
Cliff's quoted-printable text body reached the page as markup (marked `html_safe`, so `html_escape`
passed it through): fixed in `5061ee0` (upstream 1e6cd63, fe225e3, 771fb29). Cliff stderr fix
f030e1f taken (`6ce3904`): the Cliff port touches that code and the warnings flooded stderr with
megabytes per hostile email (seen in our own test runs). The unused template copies under
`lib/cliff` are kept equal to `app/views` by a test.

Own review (independent reviewer, read-only) of `7e7886a..HEAD`, fixed with tests in `1635550` and
`5f02e97`: Zippy built its links from all request parameters, so `?script_name=//host` on the first
request stored a listing whose links pointed elsewhere (now the route's parameters only, the
revision kept); inline previews let query keys set converter attributes (`?timeout=x` gave 500);
Cliff's header boxes, converted while the email page renders, turned the whole page into the 503
when no slot was free; without the cache a missing asset gave an empty 200; an empty `asset`
parameter raised TypeError; `Repository#asset_link` called `Pathname.new` with three arguments
(pre-existing, hid repository emails with stored attachments); attachments named `.` or `..`;
Vince logged a card's values. Not changed, recorded: the email page still converts the header
boxes on every view (bounded by the slots now; upstream does the same); Ruby converters (Zippy's
walk, Vince) are bounded in size, not in time (as upstream); `<dir>.lock` files stay (by design,
small); Vince's escaping round-trip (upstream e53dd40) and Cliff's Cc row for a String value are
display issues, not security.

Not ported, differences to upstream 6.1.2 that stay (Jan: keep our sandbox CSP): upstream's CSP
`default-src 'none'; img-src 'self' data:` for HTML previews and its inline scrubber dropping
off-site `<img src>` (4d18e6f) and the `name` attribute (c1d719f). Ours sandboxes without a
`default-src`, so an HTML email or document may still load remote images when previewed (no
scripts, opaque origin). A candidate for a later decision.

Behaviour to know: an email beyond Cliff's limits is not answered with 413 as the decision text
says, but with its preview stating the reason (upstream's design; the e2e checks the text). A
refused or failed preview inside the `<object>` frame (embedding 0) shows an empty frame: browsers
render no error body there (as for 404 and 503 before).

## After the upgrade (production)

Actions the person doing the upgrade must take, or know about, for this plugin:

- Hand pdf, images, text, md and textile back to Redmine, and switch pass and mark-html off (Jan,
  2026-10-07, q3 "Advies volgen"), once, after the deploy:
  `RAILS_ENV=production bundle exec rake redmine_more_previews:use_core_previews`
  (first with `DRY_RUN=1` to see the list; a second run reports "Nothing to change"). Libre,
  cliff, zippy and vince stay as configured. Install LibreOffice on the server for libre; core
  needs Pandoc for its own Office preview and for mark.
- Remove the 5.1 repository preview cache once: `rm -rf <redmine>/tmp/more_previews/repository`
  (5.1 kept repository previews in `repository/gits/<identifier>/<path>`, shared between projects with
  the same identifier; Redmine 7 builds them on demand in `repository/gits/<id>/<revision>/<path>`.
  Identifiers cannot be all digits, so the two do not meet, but the old files are never read again).
  Simplest is the next step, which empties the whole cache.
- If Maggie stays in use (it is off after the hand-over task): Ghostscript 10.03.1 or later, or a
  distribution package with its -dSAFER fixes backported (Ubuntu 24.04: `10.02.1~dfsg1-0ubuntu7.9`
  carries CVE-2024-29510 and later, while `gs --version` still prints 10.02.1), and in
  ImageMagick's `policy.xml` the coders PS, PS2, PS3, EPS, EPI, EPSI, EPSF, MVG, MSL, TEXT, URL, HTTP,
  HTTPS and FTP disabled (from curecodejp's README; they do not stop PostScript reaching Ghostscript
  through the PDF coder, which Maggie's start-of-file check does).
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
- Conversion limits (round 5; Administration > Plugins > More previews > Conversion limits, Cliff
  and Zippy have their own): the defaults are upstream's and fit GEOxyz: time limit 60 s (Libre at
  least 120 s; raise it if office documents of several hundred pages must be previewed), wait 5 s,
  2 conversions at once over all Redmine processes, repository files 50 MiB, previews 100 MiB, cache
  10 GiB, failures remembered 10 min; Cliff 50 MiB / 1,000 parts / 1,000 attachments, Zippy 10,000
  entries / 1 GiB unpacked / 100 MiB per entry / 1 GiB stored per archive. Raise "conversions at
  once" only with CPU and memory to spare; with several Redmine servers on one shared
  `tmp/more_previews` (NFS) the count may hold per server only.
- Memory (upstream 854355f): a preview is served from memory, up to 100 MiB, and requests for cached
  previews are not bounded by the conversion count, so a server may need that limit times the
  requests it serves at once (Puma/Passenger processes times threads). Each Cliff conversion forks a
  child stopped at 1 GiB of resident memory growth (address space limit twice that); with 2 conversions at once plan about 2 GiB on top of
  Redmine for the worst case. Where memory is short, lower "Largest preview served" or the
  number of processes and threads.
- Schedule the cache clean daily, f.i. in the Redmine user's crontab:
  `17 3 * * * cd <redmine> && RAILS_ENV=production bundle exec rake redmine_more_previews:cache:clean DAYS=30`
  (removes previews cached more than 30 days ago and failures remembered longer than their time;
  a preview in use is skipped and removed on the next run).
- Only administrators can reload a preview or ask for Cliff's unsafe preview now; tell the users
  the "Update" link is gone for them.

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

