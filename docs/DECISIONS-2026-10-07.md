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
