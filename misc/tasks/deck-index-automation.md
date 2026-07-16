# Deck Index Automation

## Status

Decided for now: manual script, no automation. Revisit if deck contribution
frequency increases or `discere-data` gets outside contributors who shouldn't
need repo-maintainer involvement for every merge.

## Context

Online deck import (`RemoteDeckService.fetchRemoteDecks()`) reads a single
combined `data/decks/index.json` from the `discere-data` repo on Codeberg
instead of listing the directory and fetching every deck file individually
(the previous approach was 1 listing request + N per-deck requests).

`index.json` is generated from the individual `data/decks/*.json` files by
`scripts/build_deck_index.py` in `discere-data`, which also derives:

- `sourceId` — filename stem, a stable catalog identifier. Deliberately not
  named `id`: the Flutter app's `CreateDeck.id` is reused as the local SQLite
  primary key on import (`deck.id ??= _uuid.v4()` in
  `lib/learning/repository/deck_repository.dart`), so a populated `id` from
  the remote source would collide across repeated imports.
- `updatedAt` — ISO 8601 timestamp of the last git commit touching that deck
  file (`git log -1 --format=%cI -- <file>`), falling back to "now" for
  uncommitted files.

The open question was only ever: **who/what runs
`build_deck_index.py` and pushes the result**, since `discere-data`'s `main`
branch is protected and has no CI runner attached.

## Constraint

Contributor experience must stay trivial: add a deck JSON file under
`data/decks/`, open a PR. No contributor should ever need to run a script or
touch `index.json`.

## Options Considered

1. **Forgejo Actions, self-hosted runner.** This repo had exactly this before
   (`.forgejo/workflows/generate-index.yml`, commit `e5c13b2`) and removed it
   later (commit `0912a03`) — at the time the app didn't consume `index.json`
   at all, so the generated file was dead weight. The workflow itself was
   fine and could be reinstated close to as-is.
   - Needs a runner that's reachable when a job is queued. Doesn't need a
     public IP or to run at the moment of the push — Codeberg queues the job
     server-side and any runner that later polls in will pick it up. An
     NAS that isn't on 24/7 would work in an eventually-consistent way: a
     deck merged while the NAS is off just waits until it's next powered on.
   - Unverified: whether Codeberg/Forgejo drops queued Actions jobs after some
     retention window if no runner claims them in time. Check before relying
     on this if the NAS is off for extended periods.
   - Not usable right now — no always-on (or regularly-on) machine available.

2. **Codeberg CI (Woodpecker), shared community runners.** Codeberg's
   documented recommendation for hosted CI instead of self-hosted Forgejo
   Actions runners.
   - Requires a manual access request reviewed by a Codeberg volunteer —
     not self-service, no guaranteed turnaround.
   - Different pipeline format than Forgejo Actions; the old workflow file
     can't be reused as-is.

3. **Migrate `discere-data` to GitHub, use GitHub Actions.** Mature, free
   hosted runners for public repos, and the existing workflow YAML
   (`actions/checkout`, shell steps, commit+push) is close to directly
   portable.
   - Requires moving off Codeberg (or maintaining a two-way mirror, which is
     its own source of drift/failure) and updating the app's hardcoded
     Codeberg URL (`RemoteDeckService._indexUrl`).
   - Bigger structural change than the actual problem warrants.

4. **Standalone serverless cron job** (e.g. a Cloudflare Worker using a Cron
   Trigger, independent of any HTTP-serving code). Decoupled from any git
   host's CI:
   - Periodically calls the Codeberg Contents API to read `data/decks/*.json`,
     regenerates `index.json` in the same shape as the Python script, and
     writes it back via the Contents API (SHA-based optimistic concurrency)
     using a Codeberg personal access token stored as a secret, scoped to
     `discere-data` only.
   - No uptime dependency on any of our own hardware; free-tier cron
     frequency is more than sufficient for this update cadence.
   - See also `iucn-red-list-enrichment.md` — that task independently needs a
     small always-on serverless proxy for the IUCN API key. If that gets
     built, this cron job could live in the same Worker project (two
     handlers: `fetch` for the IUCN proxy, `scheduled` for this). Not a
     requirement to bundle them; two small deployments are equally fine.
   - Not built. Worth doing if manual sync becomes a real pain point.

5. **Manual maintainer script (current choice).** `discere-data/scripts/
   sync_index.sh`: pulls `main`, runs `build_deck_index.py`, commits and
   pushes if `index.json` changed.
   - Zero infrastructure, works today.
   - Requires remembering to run it after merging a deck PR — acceptable
     because `main` is protected and every merge already requires manual
     maintainer review/approval, so this is one more step in a process that
     was never going to be hands-off anyway.

## Decision

Stay on option 5 for now. Revisit options 1 or 4 if:

- deck contribution frequency increases enough that forgetting to sync
  becomes a recurring problem, or
- `discere-data` gets contributors beyond the current maintainer who need the
  index kept fresh without depending on a manual step, or
- the IUCN proxy (see `iucn-red-list-enrichment.md`) gets built, making option
  4 close to free to add.
