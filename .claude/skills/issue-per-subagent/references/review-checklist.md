# Review checklist

The subagent's report is a claim, not a result. Past reports were cleanly
written and looked complete, and in four of five cases the review still found
the most important defect: six tautological tests that compared the database
with itself (#250), a silent failure the PR itself would have introduced
(#262), an asymmetry closed only halfway (#264), a user decision that never
reached the subagent (#279). So read the diff, not the report.

## 1. Recompute the load-bearing claims

- `git log --oneline main..<branch>` and `git diff main...<branch> --stat` —
  are the commits the ones the report lists? Anything unexpected in the
  stat (generated files, unrelated reformatting from `dart format`, a stray
  diagnostic change in `lib/`)?
- Run `flutter analyze`, `flutter test test/architecture/` and the touched
  test directories yourself. Don't quote the subagent's numbers as yours.
- **Redo at least one red-check yourself**, ideally the one that carries the
  issue's core behaviour. Sabotage exactly the behaviour, confirm it compiles,
  confirm the *expected* test fails on a *content* assertion (read the
  message), restore, `git status` clean. A red-check that turns *something*
  red proves nothing — at #264 a `sed` that didn't match flipped an unrelated
  test, and it looked like success.
- Read each new test and ask: what would make it fail? If the answer is
  "nothing the production code does" (it asserts its own fixture, a mock's
  stub, or the DB against itself), it's a tautology.

## 2. Does it do what the issue asked — all of it?

- Every point of "Zielverhalten" and "Vorgegebener Schnitt": present, or
  deviation reported with a reason that holds?
- Every decision the user made during the run (relayed via SendMessage) —
  actually in the code? A message to a running subagent can arrive too late
  to change what it already built (#279's chip placement).
- Symmetric cases: if the fix applies to A, does the same problem exist at
  its sibling B (species vs. taxonomy detail, import vs. create, online vs.
  offline)? Half-closed asymmetries are a recurring finding.
- New silent failure paths: `catch` that swallows, a `null` that ends a flow
  without feedback, work that moved into a `try` it doesn't belong in (#281's
  tutorial scheduling turned a load success into a load failure).

## 3. Clean code beyond the rules

The ARCH rules are a floor, not a ceiling. Hold the change to the standard
of a careful maintainer:

- **Naming says what it does.** `_resolveImagesOfNewSpecies` resolved the
  whole list *because* one species was new → misleading scope. Structural
  suffixes (`Page`, `Tab`, `Section`, …) per `docs/architecture-overview.md` §2.
- **Consistency.** Two pages with the same feature get the same interface. A
  helper introduced in the PR is used at every equivalent call site. Two
  constants that must stay equal are coupled (`= Other.optionCount`), not two
  unconnected `4`s.
- **No dead remains**: removed method's tests, l10n keys, imports, a
  parameter that shadows `State.context` for no reason, orphaned comments.
- **Comments and test names** in English, justify the current design, no
  history ("replaces the old…", "now that…"). Test names count as docs.
- **Placement** follows ownership (who actually calls it), not file type.
- **Widget splitting**: new large private widgets in a page file → own files.
- **Derived state** in a presenter, not inline in `State`.
- Diff of existing files is minimal and in the file's own format (no
  whole-file reformat).

## 4. Housekeeping

- What's New: needed (user-visible?) → both locales, right prefix, `wc -m`
  ≤ 500 for both files. Not needed → nothing added.
- Tutorials: any `GlobalKey` target moved/removed, any description now wrong?
- Docs (`CLAUDE.md`, `docs/`, module READMEs) still true? Present state only.
- New integration test file → `all_tests.dart` + exactly one CI shard.
- Commit messages: German, functional, **no AI attribution** — check with
  `git log --format=%B main..<branch> | grep -i -E 'co-authored|generated|claude'`.

## Rework message (SendMessage to the same subagent)

Keep using the agent that did the work — it has the context. One message per
review round:

```markdown
Review zu #<n>: <was trägt, in einem Satz; welche Rot-Probe du selbst
nachgerechnet hast>. <k> Nacharbeiten auf `<branch>`:

1. **<Kurztitel>.** <Befund mit Datei/Stelle, warum es ein Problem ist,
   konkretes Szenario. Was genau zu tun ist. Wenn du einen sachlichen Grund
   siehst, warum das schlechter ist: berichte ihn statt umzubauen.> Test +
   Rot-Probe: <…>. Gehört in Commit `<sha>` (Fixup).
2. …

Nicht anfassen: <Dinge, die du gesehen und bewusst so gelassen hast>.

Wie gehabt: deutsch, keine AI-Attribution, nicht pushen, kein PR, kein
`dart format` über bestehende Dateien. Fixups per `git commit --fixup <sha>`
+ `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash main` (interaktives
rebase ist nicht verfügbar) oder eigener Commit, wenn das sauberer ist – sag,
was du gemacht hast. Danach `flutter analyze`, `flutter test
test/architecture/`, <betroffene Tests / `flutter test` komplett>. Bericht:
Diff-Ausschnitte, Rot-Probe mit Meldung, neue Commit-Hashes, rohe
Ergebniszeilen.
```

Acknowledge what the subagent got right when it's true — including where its
approach beat your prescribed cut (#227). It keeps the next report honest
rather than defensive. Then re-review the rework with the same rigour; stop
when a round produces no findings.
