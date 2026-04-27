# Discere – Architecture Overview

## 1. What is Discere?

Discere is a **Flutter-based flashcard app** (Android + iOS) for learning biological species (primarily marine life). Users create or import decks of species, review flashcards using a spaced-repetition algorithm (FSRS-4.5), and track their learning progress. The app supports offline use, push notifications for due reviews, deck sharing via QR / JSON / text, and full DE/EN localization.

---

## 2. Architectural Style

Discere follows a **layered Service-Repository architecture** with `provider` for dependency injection and state management. It is _not_ BLoC, _not_ Clean Architecture, and _not_ MVVM in a formal sense — though it shares traits with all three.

The closest label is:

> **Service-Oriented Layered Architecture with Provider-based DI**

### Key characteristics

| Trait | In Discere |
|---|---|
| **Dependency Injection** | Manual constructor injection; wired in `main.dart` → `setupServices()` and exposed via `MultiProvider`. |
| **State propagation** | `ChangeNotifier` + `Consumer` / `Provider.of`. Some services are `ChangeNotifier`, others are plain `Provider`. |
| **Data flow** | UI → Service → Repository → SQLite (via `DatabaseHelper`). |
| **Navigation** | Imperative `Navigator.push` with `MaterialPageRoute`. No declarative router. |
| **Separation of concerns** | Good vertical separation (model / persistence / service / UI). No horizontal feature-module boundaries. |

---

## 3. Layer Diagram

```
┌────────────────────────────────────────────────────────┐
│                        UI Layer                        │
│  pages/  •  components/  •  widgets/  •  search delegate│
│  (StatefulWidget + FutureBuilder + Consumer)           │
└────────────────────┬───────────────────────────────────┘
                     │  Provider.of / Consumer
┌────────────────────▼───────────────────────────────────┐
│                    Service Layer                       │
│                                                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ learning/    │  │ common/      │  │ external/    │  │
│  │ DecksService │  │ ImageService │  │ WikiService  │  │
│  │ FlashcardSvc │  │ FavoriteSvc  │  │              │  │
│  │ FsrsService  │  │ WatchlistSvc │  └──────────────┘  │
│  │ RemoteDeckSvc│  │ NotifSvc     │                    │
│  │ ImportExport │  │ LanguageSvc  │                    │
│  └──────────────┘  │ UserPrefsSvc │                    │
│                    └──────────────┘                    │
└────────────────────┬───────────────────────────────────┘
                     │  direct method calls
┌────────────────────▼───────────────────────────────────┐
│                 Persistence Layer                      │
│                                                        │
│  DatabaseHelper (static, dual-DB singleton)            │
│  DeckRepository  •  FlashCardStatRepository            │
│  SpeciesRepository  •  SearchRepository                │
│  SourceRepository                                      │
└────────────────────┬───────────────────────────────────┘
                     │  sqflite
┌────────────────────▼───────────────────────────────────┐
│               Data / Storage                           │
│                                                        │
│  discere_reference.db  (read-only, bundled asset)      │
│  discere_user.db       (read-write, user data)         │
│  SharedPreferences     (favorites, watchlist, prefs)   │
│  Local filesystem      (cached images, deck covers)    │
└────────────────────────────────────────────────────────┘
```

---

## 4. Layer Breakdown

### 4.1 UI Layer (`lib/ui/`)

| Folder | Purpose |
|---|---|
| `pages/` | 13 full-screen pages (home, deck, create deck, import, edit, share, settings, species detail, watchlist, favorites, sources, coming-soon) |
| `components/` | 13 reusable widgets (deck card, flashcard front/back, image carousel, image picker, glass container, …) |
| `widgets/` | Empty — currently unused. |
| `search_species_delegate.dart` | Custom `SearchDelegate` for species full-text search. |

**UI state management patterns used:**
- `FutureBuilder` for one-shot async loads (deck lists, stats, flashcards).
- `Consumer<T>` for reactive rebuilds when `ChangeNotifier` services change.
- Local `StatefulWidget` state for form inputs, animation, FAB expansion.
- `setState()` after navigation returns to force re-fetch.

### 4.2 Service Layer (`lib/service/`)

Split into two sub-packages:

| Package | Services | Responsibility |
|---|---|---|
| `learning/` | `DecksService`, `FlashCardService`, `FsrsService`, `SpacedRepetitionService`, `RemoteDeckService` | Core learning domain: deck CRUD, card scheduling, FSRS algorithm, remote deck fetching |
| `common/` | `ImageService`, `FavoriteService`, `WatchListService`, `LanguageService`, `NotificationService`, `ImportExportService`, `SourceService`, `UserPreferencesService` | Cross-cutting shared services |

**Notable:** `DecksService` is a `ChangeNotifier` (calls `notifyListeners()` after mutations). Most others are plain services injected via `Provider.value`.

### 4.3 Persistence Layer (`lib/persistence/`)

- **`DatabaseHelper`** – Static singleton managing two SQLite databases:
  - `discere_reference.db` (read-only, copied from assets, versioned)
  - `discere_user.db` (read-write, schema v2 with deck + flashcard_stats tables)
- **5 Repositories** – Each owns raw SQL queries and `Map ↔ Model` mapping.
- Repositories access the database getter `DatabaseHelper.userDb` / `DatabaseHelper.referenceDb` directly — no abstraction layer or interface.

### 4.4 Model Layer (`lib/model/`)

| Sub-package | Contents |
|---|---|
| `biology/` | `Species`, `Classification`, `Picture`, `SpeciesWithLocalImages` |
| `learning/` | `BaseDeck`, `FlashCardStat`, `DeckStat` |
| `common/` | `AppException` hierarchy, `JsonEncodable` |
| `ui/` | `ViewDeck`, `CreateDeck` (view-models / DTOs) |
| `search/` | `SearchResult` |
| Root | `Language` enum, `Source` |

**Serialization:** `json_serializable` with `build_runner` for `BaseDeck`, `CreateDeck`, `SearchResult`. Manual `_toMap / _fromMap` in repositories. Mixed approaches.

### 4.5 External Layer (`lib/external/`)

- `wiki/` — `WikiService` + `WikiImage` model for Wikimedia Commons image search.

### 4.6 Supporting Modules

| Module | Purpose |
|---|---|
| `theme/` | `OceanTheme` (dark, ocean-blue) + `OceanColors` + `AppSpacing` constants |
| `extensions/` | `LocalizationExtension` (`context.loc`) |
| `util/` | `Constants`, `JsonExportUtil` (gzip) |
| `l10n/` | ARB-based localization (DE + EN) |
| `etl/` | Data pipeline tooling (separate from main app) |

### 4.7 Enrichment Semantics

The post-import enrichment pipeline is intentionally **checkpointed and
terminal-state driven**.

Relevant building blocks:

| Component | Responsibility |
|---|---|
| `INatEnrichmentQueueService` | schedules foreground/background processing and derives the user-visible status |
| `EnrichmentJobExecutor` | executes stages and persists per-stage checkpoints |
| `EnrichmentJobRepository` | stores `remainingSpeciesIdsByStage`, progress, leases, and stage states |
| `EnrichmentService` | performs the actual photo/common-name fetches and writes caches |

Important rule:

> A species may only be marked complete for a stage once it reached a
> **terminal outcome**.

Terminal means one of:
- the enrichment data was written successfully
- an explicit no-result marker was written

Examples:
- `inat_photo_cache` stores `__empty__` when iNaturalist has no usable photos
- `runtime_common_names` stores a synthetic no-result marker when the taxon was
  resolved but no common names exist

Image-download concurrency is also intentionally split by source:
- reference images (`reference_images`, e.g. FishBase / SeaLifeBase) may be
  downloaded in parallel
- external runtime images (`external_images`, currently dominated by
  iNaturalist-hosted media) are downloaded **serially**

Why this matters:
- iNaturalist is much more sensitive to bursty traffic and rate limits than the
  static reference-image sources
- parallel iNaturalist image fetches produced little practical throughput gain
  but noticeably increased device heat, network spikes, and retry churn
- serializing iNaturalist media downloads keeps the app friendlier to the
  upstream API/host while still letting reference-image imports finish quickly

Why this matters:
- transient iNat/network failures must **not** silently advance the checkpoint
- taxonomy/name mismatches must **not** cause a stage to be marked `succeeded`
  just because the runner loop finished
- if a species is not terminal yet, it must remain in
  `remainingSpeciesIdsByStage` so the queue can yield and retry later

This rule is the guardrail against false-success states such as:
- banner disappears
- deck job is `completed`
- but some species still have no iNat photo cache / no common-name outcome

### 4.8 Target Design: Import-Wide iNaturalist Enrichment

The current queue is still primarily **deck-centric**:
- one enrichment job per deck
- stage-local chunking per deck
- taxonomy common-name dedupe only within the current chunk

For large imports with overlapping decks this leaves substantial optimization
potential unused. The target design is therefore **import-wide and species-
centric**, while still projecting the results back onto individual decks.

Core modeling rules:
- species work is modeled primarily by `speciesId`
- iNaturalist dedupe happens only after a stable `taxon_id` exists
- taxonomy work is keyed preferably by `rank + taxon_id`, with
  `rank + scientific_name` only as a fallback before iNat resolution

Suggested import-wide collections / queues:

| Collection / Queue | Key | Purpose |
|---|---|---|
| `speciesWork` | `speciesId` | global species node with `deckIds`, `deckCount`, scientific-name candidates, per-stage states, and retry metadata |
| `taxonResolveMemo` | normalized scientific-name candidate | remembers successful/failed iNat taxon resolution attempts during the current import run |
| `taxonomyWork` | `rank + taxon_id` (fallback `rank + scientific_name`) | deduplicated taxonomy nodes for genus / family / order / class common names |
| `photoPrimaryQueue` | species priority score | fetch one good primary iNat image per species first |
| `speciesCommonNameQueue` | species priority score | fetch species-level common names only after taxon resolution is terminal |
| `taxonomyCommonNameQueue` | taxonomy priority score | fetch taxonomy-level common names only after the relevant species have stable iNat resolution |
| `photoBackfillQueue` | low-priority species score | optional enrichment of additional iNat images after primary coverage is done |

Recommended processing order:

```text
1. Build global speciesWork from the imported decks
2. Prioritize species by value (deckCount, missing primary image, known taxon_id, visible deck, retry state)
3. Run primary iNat photo coverage first
4. Run species common names second
5. Build deduplicated taxonomyWork only from successfully iNat-resolved species
6. Run taxonomy common names third
7. Run photo backfill last and at lower priority
```

This order intentionally follows a "good enough first" principle:
- first get one useful image per species
- then get species-level common names
- only afterwards spend requests on taxonomy names and photo backfill

Expected architectural benefits:
- overlapping species across multiple decks are resolved only once per import
  run instead of once per deck / per chunk
- higher-frequency species can be prioritized because one successful iNat
  result helps multiple decks immediately
- taxonomy common-name traffic can be deduplicated globally instead of only
  inside the current chunk
- backfill becomes an explicitly lower-priority luxury stage instead of an
  implicit continuation of the primary photo stage
- endpoint budgets (`taxa`, `observations`, `taxon_names.json`) can be managed
  more deliberately because the work graph is no longer hidden behind
  deck-local loops

State handling should remain explicit for both species and taxonomy nodes:
- `pending`
- `running`
- `done`
- `noResult`
- `retryScheduled`
- `permanentFailure`

This preserves the current "terminal outcome only" rule while moving the
enrichment orchestration from a deck-local queue model toward an import-wide
deduplicated work graph.

### 4.9 Incremental Migration Plan for the Current Codebase

The target design above should **not** be implemented as a single rewrite.
The current enrichment stack already contains valuable and battle-tested
pieces:
- `INatEnrichmentQueueService` knows how to coordinate foreground/background
  execution and user-visible state
- `EnrichmentJobRepository` already persists leases, retries, checkpoints, and
  stage states safely
- `EnrichmentService` already owns the iNaturalist-specific fetch logic and the
  terminal/no-result semantics

The safest migration path is therefore to keep these responsibilities in place
and change the **shape of the work graph** step by step.

#### Phase 1 — Reduce duplicate work inside the current deck job model

**Goal:** lower request volume without changing the top-level job model yet.

Changes:
- deduplicate taxonomy common-name work at least for the entire current deck
  job, not only for the current `names` chunk
- add run-local `taxonResolveMemo` so repeated scientific-name resolution
  attempts are reused during one import/enrichment run
- keep the current `EnrichmentJobRepository` stage model (`base`,
  `inatPrimary`, `names`, `inatBackfill`) unchanged

Primary files:
- `lib/enrichment/service/enrichment_job_executor.dart`
- `lib/enrichment/service/enrichment_service.dart`
- `lib/enrichment/repository/enrichment_job_repository.dart`

Expected value:
- immediate reduction of duplicate `taxa` and taxonomy common-name requests
- low behavioral risk because deck-local checkpoints and retries stay intact

#### Phase 2 — Introduce import-scoped species work assembly

**Goal:** stop treating overlapping decks as unrelated iNat work sources.

Changes:
- build an import-scoped `speciesWork` collection before deck jobs fan out
- key this collection by `speciesId`
- attach:
  - `deckIds`
  - `deckCount`
  - scientific-name candidates
  - known `taxon_id`
  - per-capability states (`photoPrimary`, `speciesNames`, `photoBackfill`)
- allow multiple deck jobs to reference the same species-work node instead of
  independently rediscovering it

Primary files:
- `lib/learning/service/deck_import_service.dart`
- `lib/enrichment/service/inat_enrichment_queue_service.dart`
- `lib/enrichment/repository/enrichment_job_repository.dart`

Expected value:
- overlapping species across multiple imported decks are resolved once instead
  of once per deck
- higher-value species can be prioritized based on `deckCount`

#### Phase 3 — Split species work from taxonomy work explicitly

**Goal:** prevent taxonomy common-name traffic from being coupled too early to
species chunk processing.

Changes:
- make species-level common names and taxonomy-level common names separate work
  streams
- only build `taxonomyWork` from species that have a stable iNat resolution
- key taxonomy work by:
  - preferred: `rank + taxon_id`
  - fallback: `rank + scientific_name`
- keep taxonomy nodes independent from the chunk that happened to discover
  them

Primary files:
- `lib/enrichment/service/enrichment_service.dart`
- `lib/enrichment/service/enrichment_job_executor.dart`
- `lib/enrichment/repository/runtime_common_name_repository.dart`
- `lib/catalog/repository/external_id_cache_repository.dart`

Expected value:
- much better dedupe for `genus / family / order / class`
- fewer false duplicates caused by same-name-but-different-taxon situations

#### Phase 4 — Re-prioritize the work graph around "good enough first"

**Goal:** get high-value results earlier and move expensive enrichment later.

Changes:
- prioritize `photoPrimaryQueue` before all other iNat work
- then run `speciesCommonNameQueue`
- then run `taxonomyCommonNameQueue`
- move `photoBackfillQueue` into a clearly lower-priority class
- use a score, not only `deckCount`, for species ordering:
  - number of affected decks
  - no image yet
  - known `taxon_id`
  - currently visible/foreground deck
  - current cooldown / recent failures

Primary files:
- `lib/enrichment/service/inat_enrichment_queue_service.dart`
- `lib/enrichment/service/enrichment_job_executor.dart`
- `lib/enrichment/repository/enrichment_job_repository.dart`

Expected value:
- one useful image per species arrives much earlier
- common user-visible progress improves before the expensive tail work begins

#### Phase 5 — Keep persistence, retries, diagnostics, and projection deck-aware

**Goal:** preserve robustness while the work model becomes more global.

Changes:
- keep retry/backoff and terminal outcome tracking explicit per work node
- continue projecting global enrichment results back onto per-deck UI state
- extend diagnostics to report:
  - how many species were shared across decks
  - how many requests were avoided through species/taxonomy dedupe
  - how many species became fully enriched vs. partially enriched

Primary files:
- `lib/shared/repository/local_diagnostics_repository.dart`
- `lib/shared/service/local_diagnostics.dart`
- `lib/enrichment/service/inat_enrichment_queue_service.dart`
- `lib/learning/decks/*`

Expected value:
- the refactor remains observable and debuggable
- deck-level UX stays understandable even when execution becomes import-wide

#### Practical recommendation

The most realistic sequence for the current codebase is:

```text
Phase 1  -> remove duplicate work inside the current model
Phase 2  -> introduce import-scoped speciesWork
Phase 3  -> separate taxonomyWork from species work
Phase 4  -> re-prioritize around primary photo coverage first
Phase 5  -> harden diagnostics and deck projection
```

This keeps the current queue/retry/checkpoint infrastructure alive while
moving progressively toward an import-wide deduplicated enrichment graph.

---

## 5. Codebase Statistics

| Metric | Value |
|---|---|
| Dart source files (`lib/`) | ~81 (incl. generated) |
| Total lines of code (`lib/`) | ~10 850 |
| Pages | 13 |
| Reusable components | 13 |
| Services | 14 |
| Repositories | 5 |
| Models / DTOs | ~14 |
| Unit test files (`test/`) | ~18 |
| Integration test files (`integration_test/`) | 18 |
| Supported languages | DE, EN |
| State management | `provider` (ChangeNotifier + plain Provider) |
| Database | sqflite (dual-DB: reference + user) |
| SRS algorithm | FSRS-4.5 (with legacy SM-2 still present) |

---

## 6. Strengths of the Current Architecture

1. **Clear layer separation** — UI never touches SQLite directly; services mediate all business logic.
2. **Proper DI wiring** — Single setup point in `main.dart` makes service graph visible and testable.
3. **Good domain modeling** — Biology taxonomy (Species → Genus → Family → Order → Class) is well-represented.
4. **FSRS-4.5 implementation** — Modern spaced-repetition algorithm with thorough documentation and correct math.
5. **Localization** — Full i18n with ARB files and `context.loc` extension.
6. **Comprehensive integration tests** — 18 integration tests covering most user flows.
7. **Theming** — Centralized `OceanTheme` with consistent design tokens.
8. **Error hierarchy** — `AppException` subtypes for network, server, and format errors.

---

## 7. Architectural Concerns (Summary)

> Detailed improvement tasks are in [`misc/tasks/architecture-improvements.md`](./tasks/architecture-improvements.md).

| Area | Concern |
|---|---|
| **Testability** | Repositories use static `DatabaseHelper` — hard to mock without DI. Services are concrete classes, no interfaces. |
| **Static singletons** | `DatabaseHelper` with mutable static state creates implicit dependencies and makes teardown fragile. |
| **Mixed serialization** | Some models use `json_serializable`, others manual map conversion. |
| **Dead code** | `SpacedRepetitionService` (SM-2) is still present but unused; `widgets/` directory is empty; `app_theme.dart` is 1 byte. |
| **Service coupling** | `FlashCardService.reviewCard()` triggers global notification rescheduling on _every single card review_ — 10× DB query per session. |
| **UI state** | Heavy use of `FutureBuilder` with futures created in `build()` → unnecessary re-fetches on every rebuild. |
| **Navigation** | Imperative `Navigator.push` everywhere, no type-safe routing. |
| **Missing repository interfaces** | Services depend on concrete repositories, not abstractions. |
