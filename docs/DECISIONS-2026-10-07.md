# Decided by Jan, 2026-10-07

Jan Catrysse answered the open questions of this plugin on 2026-10-07, one at a time, with the
options, an explanation and the recommendation in front of him, in the coordinating session that
started the migration sessions (https://claude.ai/code/session_01GiSsYPm3bxvqrpZkdCxNoi).
This file records his answers as given; his free-text notes are quoted verbatim. The migration
session moves each into docs/REDMINE7-MIGRATION.md as decided and builds what it requires.

General decisions by Jan (2026-10-07), for every GEOxyz plugin:
- GEOxyz goes straight to Redmine 7: no backports to 5.1. Nothing is cherry-picked to the default branch or to the branch production runs today; `redmine70-migration` is what goes live with Redmine 7. Redmine 5.1 compatibility is no longer a requirement; drop that rule from the plan and do not add code paths that exist only for 5.1.
- GEOxyz does not use MariaDB or MySQL; production runs PostgreSQL 16. Run the tests and the e2e set on PostgreSQL only. Keep SQL portable where that costs nothing, but MariaDB runs are no longer required and a MariaDB-only problem is a note in the plan, not a blocker.
- A plugin that depends on deface requires it without a version constraint (change it when the Gemfile is touched anyway).
- A Redmine core method that other installed plugins also patch is patched with `prepend`, never with `alias_method`. Mixing both on one method recurses; that is what made Project > Settings return HTTP 500 with all GEOxyz plugins installed. Check this plugin: if it patches such a method with `alias_method`, switch it to `prepend` with a test, and confirm Project > Settings, the issue list and an issue page answer 200 with the other GEOxyz plugins installed (`RMP_EXTRA_PLUGINS`).
- GitHub Actions stay manual only (`workflow_dispatch`).

Decisions for this plugin:
1. redmine_more_previews-q1: Wachtwoorden en geheime sleutels uit de serverconfiguratie vervangen na de upgrade?
   Jan chose B: "Niet nodig, alleen vertrouwde gebruikers" (Geen werk, maar alleen verantwoord als geen onbetrouwbare gebruiker ooit een previewbare bijlage kon openen.). Carry this out (see step 3).
2. redmine_more_previews-q2: Voorbeeldweergaven blijven in een afgeschermde omgeving (zandbak) draaien?
   Jan chose A: "Zandbak houden" (De beste bescherming tegen een vijandig HTML-bestand of mail; de vCard toont een ander lettertype.). Already built: keep it and record the decision.
3. redmine_more_previews-q3: Welke bestandstypes laat je na de upgrade door Redmine zelf tonen in plaats van door de plugin?
   Jan chose A: "Advies volgen" (Redmine toont pdf, beelden, tekst en md, de plugin houdt Office, mail en zip, en de converters pass en mark-html gaan uit.). Carry this out (see step 3).
4. redmine_more_previews-q4: Wat doen we met de verlaten upstream en de drie oude bibliotheken van deze plugin?
   Jan chose A: "Houden voor de upgrade, daarna beslissen" (Geen werk nu; de niet-onderhouden code blijft voorlopig in gebruik.). Already built: keep it and record the decision.
5. redmine_more_previews-q5: De nutteloze CodeQL-controle in de repository nu verwijderen of later?
   Jan chose A: "Op handmatig laten, later verwijderen" (Geen werk nu; het bestand blijft voorlopig staan.). Already built: keep it and record the decision.

What to do:
1. `git fetch && git checkout redmine70-migration && git pull`.
2. Record every decision above in docs/REDMINE7-MIGRATION.md: move it from open to decided, with the choice, the date 2026-10-07 and Jan's note verbatim where there is one. Update the plan's rules for the general decisions (no 5.1, PostgreSQL only).
3. Carry out each decision that needs a change: one commit per decision, each with a test that fails without it. A choice that says "later" or "separate change" is built now, in its own commit. A choice that says it happens after the upgrade goes under "After the upgrade". A decision that needs no code (not reporting to a vendor, accepting a loss, a role setting) is only recorded.
4. Plugin tests green on Redmine 7.0-stable-GEOxyz with PostgreSQL, alone and with the other GEOxyz plugins installed. Quote the numbers.
5. `./.codex/start_server.sh` and `./.codex/e2e.sh`: a scenario for every function a decision touches, as admin, manager, reporter and outsider, including the refusal paths. Open every screenshot, commit them in docs/e2e/ and list them in the inventory.
6. Your own adversarial review of the new commits, then `./.codex/openai_review.sh` when OPENAI_API_KEY is set; every finding gets a Resolution line. Without the key, say the review was skipped.
7. Update Status, the inventory, the work list and "After the upgrade". Push `redmine70-migration` after every commit.
8. These decisions are final; do not stop to ask about them. If one turns out to be impossible, write down why in the plan and carry on with the rest.
9. End with a short report in Dutch: per decision what you did (commit), test numbers, e2e numbers (scenarios, screenshots, problems), the review result, what is left for Jan.

## Round 4, 2026-10-11: security fixes from curecodejp/redmine_more_previews v6.1.1

Jan decided (2026-10-11) to port two of the three security fixes of
https://github.com/curecodejp/redmine_more_previews/releases/tag/v6.1.1 to
`redmine70-migration`. curecodejp is a separate fork (6.x) of the same
HugoHasenbein code; both are GPL-2. There is no shared history after 5.0.9, so
port by hand and name the upstream commit in each commit message.

1. Repository previews require `browse_repository` only (upstream 97f33d5, GHSA merge 9977d5f). PORT.
   Our bf9e6a7 made RmpPerm.push_permission honour its argument, but init.rb
   still pushes repositories/more_preview and more_asset to `view_changesets`
   as well. In Redmine 7 core `view_changesets` covers only show, revisions and
   revision; file content (entry, raw, diff, annotate) needs `browse_repository`.
   So a role with "View changesets" but without "Browse repository" can read
   file content through the preview frame and its assets. Register both actions
   under `browse_repository` only. Test: a role with view_changesets and without
   browse_repository gets 403 on the preview and on an asset (fails without the
   fix); the existing browse_repository-alone and no-permission tests stay green.

2. Repository preview cache per repository and content (upstream a3b07ae and 762bf11, GHSA merge 749d895). DO NOT PORT.
   Already solved differently by our 9088fd0 (repository id plus the revision
   the entry last changed in); the cross-project leak is closed. Record in the
   plan, with the two remaining differences as known limitations, not defects:
   a repository without revisions (Filesystem) or without fetched changesets
   can keep a stale preview; the 5.1 cache stays on disk, unread.
   Add under "After the upgrade": remove the `repository/` directory below the
   previews storage path once (the 5.1 cache, shared between projects; it is
   rebuilt on demand).

3. Maggie hands files to ImageMagick only as their own type (upstream e58d928, GHSA merge 99993f0). PORT, Maggie part only.
   Our Maggie passes a file Marcel reports as application/pdf to ImageMagick
   without checking its start, so PostScript disguised as a PDF runs in
   Ghostscript. In the PDF branch the output name is built from the file name
   (`outfile`, relative after `cd`), and in a repository that name is chosen by
   whoever commits the file: ImageMagick reads a name starting with "|" as a
   command and "-" as an option. Port:
   - refuse a PDF that does not start as one; use `Redmine::Thumbnail.valid_pdf_magic?`,
     which Redmine 7 has with the fixed check (#44145), instead of a copy;
   - read every input with the coder of its type (`jpeg:`, `png:`, `gif:`, `bmp:`, `pdf:`);
   - write to a fixed output name (`out.<format>`) with the format coder;
   - bound ImageMagick with `-limit` before the input, as upstream does.
   Tests: a PostScript file named .pdf (also one starting with a PS header
   other than %!PS) produces no ImageMagick call; a file named `|touch x.pdf`
   or `-x.pdf` gives a command with the fixed output name and coder prefixes;
   a real PDF and a PNG still convert. Each fails without the fix.
   NOT the Peek part (ad8db89): Peek goes through Redmine::Thumbnail.generate,
   which on Redmine 7 already checks the start of the file.
   Note: after `rake redmine_more_previews:use_core_previews` Maggie is off in
   GEOxyz, so this is defence in depth for when an admin turns it on again.
   Under "After the upgrade" add the server checks from upstream's README:
   Ghostscript 10.03.1 or later, and the PS/PS2/PS3/EPS/EPI/EPSI/EPSF/MVG/MSL/
   TEXT/URL/HTTP/HTTPS/FTP coders disabled in ImageMagick's policy.xml.

Do not port the other 6.1.1 changes (Zippy rev parameter, Redmine 6 icon CSS);
note them in the plan as seen and not needed or not security.

What to do: one commit per ported fix, each with its test; plugin tests green
on PostgreSQL alone and with the other GEOxyz plugins; e2e scenarios for both
(the view_changesets-only role refused on a repository preview and asset, a
browse_repository role allowed; Maggie turned on: a disguised PDF gives no
preview, a real PDF and a PNG still do), screenshots opened and committed;
your own adversarial review and `./.codex/openai_review.sh` when
OPENAI_API_KEY is set, every finding with a Resolution line; update Status,
inventory and "After the upgrade"; push after every commit; end with a short
report in Dutch. These decisions are final; do not stop to ask about them.
