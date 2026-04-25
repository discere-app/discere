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
