# Briefing template

The briefing is the only context the implementing subagent gets. It starts
cold: it has not read the issue thread, has not seen your analysis, and does
not know which traps you have already found. Whatever you leave out it has to
rediscover, and often it won't. A good briefing is long (6–14k characters is
normal for this repo) because it carries *verified facts*, not instructions
to go find them.

Write it in German, like the past briefings. Code identifiers, paths and
commands stay as they are.

## Skeleton

Use these sections in this order. Leave out a section only if it has truly
nothing to say for this issue (e.g. no UI → no tutorial check), and say so in
one line instead of dropping it silently where a reader might expect it.

```markdown
Du setzt GitHub-Issue #<n> („<Titel>") im Flutter-Projekt
`/Users/fabian/projekte/discere` um. Lies zuerst `CLAUDE.md` im Repo-Root
vollständig – Architekturregeln (ARCH-01…15), Feature-Ownership,
Presenter-Muster, Widget-Splitting, Naming in
`docs/architecture-overview.md` §2, Doku-/Kommentar-Konventionen sind
verbindlich. Die Fakten unten sind am Code geprüft (Stand `main`, Commit
<sha>). Wenn eine davon nicht stimmt oder der vorgegebene Schnitt nicht
trägt: **berichte das, statt stillschweigend anders zu bauen**.

## Das Issue
<Kern des Issues, wörtlich oder knapp zusammengefasst, Labels. Bei
Rücksprache mit dem Nutzer: seine Entscheidungen hier festhalten
(„Entschiedene Variante: …").>

## Ist-Zustand (geprüft)
<Pro beteiligter Datei: Pfad, Codezeilen + ARCH-07-Status (aus
file_budget.py), Rolle, relevante Stellen mit Namen. Aufrufer, die betroffen
sind. Was schon erledigt ist (z. B. „Der QR-Bug ist bereits behoben – nenne
den Test, der es absichert"). Toter Code, der mit wegfällt.>

**Falle:** <Jede Stelle, an der der naheliegende Weg falsch ist – und warum.
Das ist der wertvollste Teil des Auftrags.>

## Zielverhalten
<Was der Nutzer danach sieht/erlebt. Was ausdrücklich NICHT betroffen ist.
Startwerte, Randfälle, Platzierung im UI.>

## Vorgegebener Schnitt
<Nummeriert: wohin der Code gehört (Slice/Feature-Ordner/Schicht, mit
Begründung aus Ownership/ARCH-06/ARCH-11), welche Typen entstehen, was
geteilt statt kopiert wird, was umbenannt wird. Wo du dem Subagenten eine
Entscheidung überlässt: „entscheide und begründe".>

## Tests (spiegeln `lib/` 1:1)
<Welche Tests auf welcher Ebene (Unit/Widget/Repository/Integration).
Konkrete Fälle inkl. Randfälle. Bestehende Tests, die nachgezogen werden
müssen.>

- **Keine Tautologien.** Jeder neue Test muss rot werden, wenn man das
  geprüfte Verhalten entfernt.
- **Rot-Proben** mindestens für: (a) …, (b) … – je mit der konkreten
  Sabotage, die du erwartest. Eine Probe zählt nur, wenn sie **kompiliert**
  und genau der erwartete Test mit einer **inhaltlichen Assertion** scheitert
  – ein Kompilierfehler oder ein anderer roter Test beweist nichts. Danach
  wiederherstellen und per `git status`/`git diff` prüfen, dass nichts übrig
  ist.
- Integrationstests: <entweder „müssen nur kompilieren (`flutter analyze`)"
  oder „auf `emulator-5554` laufen lassen: `flutter test
  integration_test/<datei> -d emulator-5554` (setzt die Dev-App-Daten
  zurück)"; Wartestellen über `waitForFinder`/`waitForCondition` aus
  `integration_test/test_utils.dart`, keine festen Wartezeiten. Neue Datei →
  ARCH-12 (`all_tests.dart`, `group`-gescopte setUp/tearDown) und ARCH-15
  (genau ein Shard in `.github/workflows/flutter_ci.yml`).>

## Weiteres
- **What's New:** <entweder „je eine Zeile `Neu:`/`Fix:`/`Änderung:` bzw.
  `New:`/`Fix:`/`Change:` ans Ende von `distribution/whatsnew/de-DE/whatsnew`
  und `en-US/whatsnew`, ein Satz aus Nutzersicht. Danach `wc -m` beider
  Dateien – Play-Store-Limit 500 Zeichen, `release.yml` prüft das. Bei
  Überschreitung **deine** Zeile kürzen oder mit einer bestehenden gleicher
  Art zusammenfassen, andere Zeilen nicht umformulieren; Zählung berichten"
  oder „kein Eintrag – <Grund>".>
- **Tutorials:** <welche der vier Touren betroffen sein könnten; „zeigt ein
  `GlobalKey` oder eine Beschreibung auf etwas, das du verschiebst? Wenn ja
  nachziehen, wenn nein im Bericht bestätigen".>
- **Doku:** `CLAUDE.md`/`docs/` nur ergänzen, wo eine Aussage durch die
  Änderung falsch oder unvollständig wird; nur Ist-Zustand, keine Historie
  („war X, jetzt Y", „now that…", „used to", „replaces the old…" – auch in
  Code-Kommentaren, Testnamen und mitverschobenen Kommentaren).
- l10n: nur `app_de.arb`/`app_en.arb` sind versioniert, danach `flutter
  gen-l10n`; ungenutzte Schlüssel entfernen. ARCH-03: kein Exception-Text im
  UI, `describeError`.
- ARCH-07: neue Dateien < 250 Codezeilen; geschrumpfte Ratschen-Einträge in
  `test/architecture/file_size_budget_test.dart` senken (Slack 25).
- Mocks bei Bedarf `dart run build_runner build` (`test/mocks.mocks.dart` ist
  gitignored).

## Clean-Code-Erwartungen (wird streng geprüft)
- Code liest sich wie die Nachbardateien: Benennung, Kommentardichte,
  Idiome. Kommentare englisch, begründen das Warum aus dem jetzigen Zustand.
- Keine toten Reste (Imports, Parameter, Hilfsfunktionen, l10n-Schlüssel).
- Ein eingeführter Helper wird an *allen* gleichartigen Stellen verwendet,
  nicht an dreien von fünf.
- Kein Verhalten nebenbei ändern, keine Refactorings außerhalb des Auftrags.
  Was dir auffällt und nicht dazugehört: berichten, nicht anfassen.
- Keine Parameter mit zwei Bedeutungen; keine Bool-Schalter, wo ein nullable
  Callback/Slot oder ein Ergebnistyp (sealed class) reicht; keine Exceptions
  als Kontrollfluss.
- <issue-spezifische Erwartungen>

## Arbeitsweise
- `main` ist aktuell und sauber. Branch von `main`, genau so benannt:
  `<typ>/<n>-<kurzname>` (`feat/`, `fix/`, `refactor/`, `chore/`), z. B.
  `feat/342-inat-laufzeit-stammpruefung` – die Issue-Nummer gehört direkt
  hinter den Typ. Committen in sinnvollen Schritten,
  **nicht pushen, keinen PR öffnen**.
- Commit-Messages deutsch, kurz, fachlich (was/warum auf Produkt-/
  Architekturebene), keine Zeilenzahlen. **Keinerlei AI-Attribution** – kein
  `Co-Authored-By`, kein „Generated with…", auch wenn dein Tooling das
  vorschlägt.
- **Kein `dart format` über ganze bestehende Dateien** – das lokale SDK
  formatiert anders als der Repo-Stand und erzeugt riesige Fremd-Diffs. Neue
  Dateien darfst du formatieren, bestehende nur von Hand im Stil der Datei.
- Am Ende ausführen und die echten Ergebnisse berichten: `flutter analyze`,
  `flutter test test/architecture/`, `flutter test` komplett<, plus die
  genannten Integrationstests>.

## Bericht
(1) Geänderte/neue Dateien mit je einem Satz; (2) Entscheidungen und
Abweichungen vom Schnitt mit Begründung; (3) Rot-Proben: was sabotiert,
welcher Test mit welcher Meldung rot; (4) rohe Ergebniszeilen von
analyze/Tests inkl. allem Fehlgeschlagenen/Übersprungenen; (5) ARCH-07-Werte
der berührten Ratschen-Dateien und Codezeilen der neuen Dateien;
(6) What's-New-Zeichenzahlen; (7) <issue-spezifische Fragen, die du
beantwortet haben willst>; (8) alles, was dir aufgefallen ist und du bewusst
nicht angefasst hast.
```

## What makes a briefing good — from past issues

- **Name the trap, with the reason.** #279: "Die Klassifikationszeilen der
  Taxonomie sind *nicht* sprachabhängig – `localizedName` legt den Namen
  schon beim Laden fest." Without that sentence the subagent would have built
  a language switch that silently did nothing on half the page.
- **Give budget numbers, not "watch the file size".** "`taxonomy_repository.dart`
  steht mit **exakt 588** auf der Ratsche: darf nicht wachsen. Eine
  Hilfsfunktion in `common_name_merging.dart` hält die Aufrufstellen
  zeilenneutral." The subagent can plan around a number.
- **Check what is already done.** #135's headline bug had been fixed long
  before; the briefing said so and asked for the test that proves it, which
  kept the subagent from rebuilding working code.
- **State what must not change**, and how to prove it ("`SpeciesSummarySection.language`
  bleibt unverändert – prüfe es am Widget, nicht per Annahme").
- **Name the red-check you expect**, including a compilable sabotage when the
  obvious one won't compile (`final X? resolved = null;` instead of
  `return true ? …`, which loses null-promotion).
- **Explicitly out of scope** items go in the briefing as "im Bericht als
  Folgevorschlag nennen, nicht bauen" — otherwise a diligent subagent builds
  them.
- **Ask for decisions with justification** where you genuinely leave the call
  open ("entscheide, ob `SpeciesDetailPage` oder `SpeciesDetailContent` den
  State hält, und begründe") — it makes the report reviewable.
