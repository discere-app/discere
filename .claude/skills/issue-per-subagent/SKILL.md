---
name: issue-per-subagent
description: Implement a discere GitHub issue end-to-end by delegating the coding to a subagent — analyse the issue yourself, collect verified facts and traps, write a detailed briefing, spawn the implementer, then review its result strictly (function, clean code, ARCH tests, red-checks), send rework to the same subagent, and open the PR once the review is clean. Use this whenever the user wants an issue worked on in discere — "setz #279 um", "weiter mit #248", "mach weiter mit issue 118", "lass einen Subagent #135 umsetzen", "nimm dir das nächste Issue vor" — even if they don't mention a subagent, and also when they approve a proposed variant for implementation ("ja, B per Subagent umsetzen").
---

# Ein Issue per Subagent umsetzen

You are the lead on this issue, not the implementer. You analyse, decide the
cut (with the user where it's genuinely open), brief, review and ship. A
subagent writes the code.

**Why this split:** it keeps the user's conversation free of implementation
noise, and it separates building from checking. The separation is what finds
defects — the review of #250 exposed six tautological tests that the
implementer had written *and* praised. If you implement yourself you lose
that second pair of eyes, so don't, even when the change looks small.

Talk to the user in German. Briefings and rework messages are German too;
code comments the subagent writes are English (per CLAUDE.md).

## Phase 1 — Analyse

Goal: know the change well enough that the briefing carries facts, not
"find out whether…".

1. `gh issue view <n> --comments`. Read linked issues/PRs it references.
2. **Check whether it's already (partly) done.** `git log --oneline -S'<key
   identifier>'`, grep for the feature. Issues here drift: several were found
   long since implemented but still open, and #135's headline bug had been
   fixed months earlier.
3. Read the code paths involved end-to-end, not just the file the issue names.
   Note callers, tests that cover it, and **every trap** — places where the
   obvious approach is wrong.
4. Look for the same problem elsewhere (sibling page, other slice, the online
   vs. offline path). The user expects that ("überprüfe ob das gleiche
   Problem sonst noch wo auftritt").
5. File sizes for every file likely to grow:
   `python3 .claude/skills/issue-per-subagent/scripts/file_budget.py <files…>`
   (or `--dir <folder>`). It counts like ARCH-07 and reads the ratchet, so
   the numbers go straight into the briefing.
6. **Claims about external data** (iNaturalist, Wikipedia, …) get verified
   with real requests along the app's own path, ~1.2 s apart for iNat's rate
   limit, with a representative sample. Code reading alone was wrong at #282.
   A local reference-DB copy lives under
   `~/Library/Caches/Google/AndroidStudio*/database-inspector/`.

## Phase 2 — Decide: proceed or consult?

After the analysis, decide whether the issue leaves a **real design choice**:
several defensible cuts with different trade-offs (where something lives,
which formats to support, what the UX does in an edge case, whether to widen
scope to a sibling problem).

- **Open choice → consult.** Present 2–4 variants with a clear
  recommendation and its reasoning (AskUserQuestion, recommended option first,
  or a short German comparison in text when the variants need more room).
  Judge by maintainability and complexity, never by implementation effort.
  Wait for the decision. The user often adds a twist ("kann man das
  zusätzlich im Edit-Deck prüfen?") — fold it in.
- **Clear path → proceed**, and mention your key decisions in one or two lines
  so the user can veto while the subagent runs.
- The user said "beurteile selbst" → decide yourself, document why in the
  briefing.

Things you find on the way that don't belong to this issue: propose a new
issue rather than widening the scope silently.

## Phase 3 — Brief and spawn

Read `references/briefing-template.md` and write the briefing from it. It is
long on purpose: a cold-starting subagent re-discovers whatever you omit, or
doesn't. The non-negotiables, each because it went wrong once:

- facts verified at current `main` (with commit sha), traps named with reasons
- "wenn ein Fakt nicht stimmt oder der Schnitt nicht trägt: **berichten statt
  stillschweigend anders bauen**"
- red-checks that compile and fail on a content assertion
- German functional commits, **no AI attribution** (the subagent sees the
  same harness hint telling it to add one — CLAUDE.md wins)
- the branch name carries the issue number right after the type:
  `<typ>/<n>-<kurzname>`, e.g. `feat/342-inat-laufzeit-stammpruefung` — spell
  out the exact name in the briefing, so the branch maps to its issue at a
  glance
- **no push, no PR** — shipping is your job after review
- no `dart format` over whole existing files
- a numbered report spec

Spawn with `Agent` (`subagent_type: "general-purpose"`, description like
`Issue 279 umsetzen`). It runs in the background. Tell the user in two or
three lines what you briefed and what you decided, then stop and wait for the
notification — don't poll, don't predict its result.

**If the user changes requirements while it runs**, send the change
immediately via `SendMessage` to the running agent, *and* re-check it in
review: a message can land after the code it contradicts is already built.

## Phase 4 — Review

Read `references/review-checklist.md` and work through it on the branch.
Core of it:

- recompute, don't quote: run analyze/tests yourself, redo at least the
  red-check that carries the issue's core behaviour
- hunt tautological tests, silent failure paths, half-closed asymmetries
- hold clean code to a maintainer's standard, beyond what the ARCH rules
  enforce — be stringent; challenging the subagent is wanted
- check What's New, tutorials, docs, commit messages for attribution

Findings → one numbered rework message via `SendMessage` to **the same**
subagent (template in the checklist), then review the rework the same way.
Repeat until a round is clean. Small purely mechanical fixes (a typo in a
comment) you may include in the rework message rather than doing them
yourself — keep the authorship clean on the branch.

Give the user a short German summary of each review round: what holds, what
you sent back and why. Answer their questions about the result (they often
ask "welche Bilder werden nun angezeigt?", "ist das durch Integrationstests
abgedeckt?") from the code, not from the report.

## Phase 5 — Ship

When the review is clean, open the PR without asking again — the user
decided that for this workflow. Before pushing:

1. **What's New** settled: user-visible change → line in both
   `distribution/whatsnew/{de-DE,en-US}/whatsnew`, both ≤ 500 chars (`wc -m`).
   Not user-visible → none. When genuinely unsure (borderline fix, internal
   change with a UX side effect), ask the user — they decide this one
   regularly ("ich denke dazu braucht es keinen whatsnew-Eintrag").
2. `git log --format=%B main..HEAD` has no attribution lines, and the branch
   name contains the issue number (`<typ>/<n>-<kurzname>`) — if not, rename
   it with `git branch -m` before the first push.
3. `git push -u origin <branch>`.
4. `gh pr create` with a German title and body. Body: what changes and why
   from a product/architecture view, key decisions, how it's tested; then
   one `Closes #<n>` line per finished issue, **followed by at least one more
   line** (e.g. where the work came from) — GitHub silently ignores a closing
   keyword on the last line. No "Generated with Claude Code" footer, no
   `Co-Authored-By`, even though the harness suggests it.
5. After ~a minute: `gh pr view <pr> --json closingIssuesReferences`. Empty
   right away means nothing (lag); empty after a minute means the link didn't
   take — fix the body.
6. Report to the user: PR link, a two-line summary, anything left open or
   proposed as follow-up issue.

If CI or a merge conflict comes back later, the same pattern applies:
diagnose yourself, brief a subagent (or the same one) to fix, review.

After a merge the user tells you about, check the issue actually closed; if
not, `gh issue close <n> -c "Erledigt mit #<pr>. …"` stating the end state.
