# Discere – Architecture Overview

## 1. What is Discere?

Discere is a **Flutter-based flashcard app** (Android + iOS) for learning biological species (primarily marine life). Users create or import decks of species, review flashcards using the FSRS 6 spaced-repetition algorithm, and track their learning progress. The app supports offline use, push notifications for due reviews, deck sharing via QR / JSON / text, and full DE/EN localization.

---

## 2. Architectural Style

> **Service-Oriented Layered Architecture with Provider-based DI**

The app uses a **3-layer service-repository architecture** wired via Provider-based dependency injection. It is not BLoC, not Clean Architecture, and not MVVM in a formal sense — though it shares traits with all three.

| Trait | In Discere |
|---|---|
| **Dependency Injection** | Manual constructor injection; wired in `lib/app/bootstrap_app.dart` and exposed via `MultiProvider`. |
| **State propagation** | `ChangeNotifier` + `Consumer` / `Provider.of`. Some services are `ChangeNotifier`, others are plain `Provider`. |
| **Data flow** | UI → Service → Repository → SQLite (via `DatabaseHelper`). |
| **Navigation** | Imperative `Navigator.push` with `MaterialPageRoute`. No declarative router. |
| **Separation of concerns** | Vertical separation by feature module (`catalog`, `enrichment`, `application`, `learning`). Module dependency rules are enforced by architecture tests. |

---

## 3. Layer Diagram

```
┌────────────────────────────────────────────────────────────┐
│                         UI Layer                           │
│  app/  •  catalog/  •  learning/  •  enrichment/           │
│  (StatefulWidget + FutureBuilder + Consumer)               │
└────────────────────────┬───────────────────────────────────┘
                         │  Provider.of / Consumer
┌────────────────────────▼───────────────────────────────────┐
│                     Service Layer                          │
│                                                            │
│  learning/         application/       enrichment/          │
│  DecksService      SpeciesMedia       EnrichmentService    │
│  FlashcardService  Service            INatEnrichment       │
│  FsrsService                          QueueService         │
│  DeckImport/                          SpeciesPhotoService  │
│  ExportService                        NameResolution       │
│                                                            │
│  shared/                                                   │
│  ImageService  NotificationService  LanguageService        │
│  UserPreferencesService  INaturalistService                │
└────────────────────────┬───────────────────────────────────┘
                         │  direct method calls
┌────────────────────────▼───────────────────────────────────┐
│                  Persistence Layer                         │
│                                                            │
│  DatabaseHelper (static, dual-DB singleton)                │
│  DeckRepository  •  FlashcardStatRepository                │
│  DeckConfigRepository  •  DailyCountRepository             │
│  SpeciesRepository  •  SearchRepository                    │
│  INatPhotoCacheRepository  •  ExternalIdCacheRepository    │
│  ExternalIdRepository  •  SourceRepository                 │
└────────────────────────┬───────────────────────────────────┘
                         │  sqflite
┌────────────────────────▼───────────────────────────────────┐
│                Data / Storage                              │
│                                                            │
│  discere_reference.db  (read-only, bundled asset)          │
│  discere_user.db       (read-write, user data)             │
│  SharedPreferences     (language, favorites, watchlist,    │
│                         global default retention)          │
│  Local filesystem      (cached images, deck covers)        │
└────────────────────────────────────────────────────────────┘
```

---

## 4. Module Structure

The app is split into feature modules with explicit dependency rules.

### `shared/`
Generic infrastructure and cross-cutting helpers. Must remain domain-agnostic.
- `DatabaseHelper`, `ImageService`, `LanguageService`, `UserPreferencesService`
- `INaturalistService`, `LoggingHttpClient`, `Logger`
- Generic UI primitives and utilities

### `catalog/`
The reference catalog domain: species, taxonomy, search, source metadata, catalog UI.
- `SpeciesRepository`, `SearchRepository`, `SourceRepository`
- `LocalSpeciesImageService`, `WatchlistService`
- Species detail, taxonomy detail, watchlist pages

### `enrichment/`
Runtime enrichment on top of the reference catalog.
- `EnrichmentService`, `INatEnrichmentQueueService`
- `SpeciesPhotoService`, `INatNameResolutionService`
- `INatPhotoCacheRepository`, `ExternalIdCacheRepository`, `ExternalIdRepository`

### `application/`
Orchestration for workflows spanning multiple modules.
- `SpeciesMediaService` — combines photo lookup (enrichment) + local image resolution (catalog)

### `learning/`
Decks, flashcards, spaced repetition, import/export, and review flows.
- `DecksService`, `FlashcardService`, `FsrsService`
- `DeckImportService`, `ImportExportService`, `RemoteDeckService`
- `DeckRepository`, `FlashcardStatRepository`, `DeckConfigRepository`, `DailyCountRepository`
- Deck list, review session, edit deck, deck settings pages

### `app/`
Composition root and shell. Wires all modules together via `bootstrap_app.dart`.
- `BootstrapApp`, `FlashcardApp`, `MainScreenPage`
- `SettingsPage`, `AboutPage`

### Module Dependency Rules

Enforced by `test/architecture/module_dependency_test.dart`:

```
shared      → (nothing)
catalog     → shared
enrichment  → catalog, shared
application → catalog, enrichment, shared
learning    → catalog, enrichment, application, shared
app         → shared, catalog, enrichment, application, learning
```

---

## 5. Database Schema

### 5.1 User DB (`discere_user.db`) — ERD

```mermaid
erDiagram
    decks {
        TEXT id PK
        TEXT name
        TEXT description
        TEXT cover_image_path
        TEXT language
    }

    flashcard_stats {
        TEXT species_id PK
        TEXT deck_id PK
        TEXT card_state
        REAL stability
        REAL difficulty
        INTEGER step_index
        TEXT last_review_date
        TEXT next_review_date
    }

    deck_config {
        TEXT deck_id PK
        REAL desired_retention
        INTEGER maximum_interval
        TEXT learning_steps
        TEXT relearning_steps
        INTEGER new_cards_per_day
        INTEGER max_reviews_per_day
    }

    daily_counts {
        TEXT deck_id PK
        TEXT date PK
        INTEGER new_count
        INTEGER review_count
    }

    inat_photo_cache {
        TEXT species_id PK
        TEXT photo_url
        TEXT thumbnail_url
        TEXT attribution
        TEXT license_code
        TEXT fetched_at
    }

    external_identifier_cache {
        TEXT entity_key PK
        TEXT external_system PK
        TEXT external_id
        TEXT fetched_at
    }

    runtime_common_names {
        TEXT entity_key PK
        TEXT language PK
        TEXT common_name
        TEXT fetched_at
    }

    runtime_common_name_search_documents {
        TEXT entity_key PK
        TEXT scientific_name
        TEXT common_names_de
        TEXT common_names_en
    }

    runtime_common_name_search_fts {
        TEXT entity_key
        TEXT scientific_name
        TEXT common_names_de
        TEXT common_names_en
    }

    decks ||--o{ flashcard_stats : "contains"
    decks ||--o| deck_config : "configured by"
    decks ||--o{ daily_counts : "tracks daily"
```

### 5.2 Reference DB (`discere_reference.db`) — Tables

| Table | Contents |
|---|---|
| `species` | Core species entities (ID, genus, binomial name, common names) |
| `genera` | Genus taxonomy |
| `families` | Family taxonomy |
| `orders` | Order taxonomy |
| `classes` | Class taxonomy |
| `pictures` | Bundled reference images with source/license metadata |
| `sources` | Upstream data source catalog (FishBase, SeaLifeBase, …) |
| `entity_external_ids` | ETL-produced offline mapping from Discere entity keys to external IDs (e.g. iNaturalist taxon IDs) |
| `metadata` | Technical key/value import metadata (ETL version, enrichment timestamps) |

---

## 6. FSRS 6 Algorithm

Discere implements **FSRS 6** (Free Spaced Repetition Scheduler v6), the sole scheduling algorithm.

### Card States

```
newCard → [initializeNextBatch] → learning
learning → [pass step] → learning | review
learning → [fail] → learning (reset steps)
review → [fail] → relearning
relearning → [pass step] → review
```

### Key Parameters (per deck, configurable)

| Parameter | Default | Description |
|---|---|---|
| `desiredRetention` | 0.9 (global) | Target recall probability |
| `maximumIntervalDays` | 36 500 | Hard cap on review interval |
| `learningSteps` | `[1m, 10m]` | Step durations for new cards |
| `relearningSteps` | `[10m]` | Step durations after failure |
| `newCardsPerDay` | 20 | Daily limit on newly initialized cards |
| `maxReviewsPerDay` | 200 | Daily cap on review-state cards (learning/relearning uncapped) |

### Global Default Retention

A global `defaultDesiredRetention` is stored in `SharedPreferences` (key: `default_desired_retention`, default 0.9) and editable on the Settings page. When a new deck is created or imported, a `deck_config` row is stamped immediately with the global default via the `DecksService.onDeckCreated` callback. Individual decks can override this via the Deck Settings page.

### Stability & Difficulty

FSRS 6 maintains two per-card parameters:
- **Stability** (`s`) — expected half-life of the memory trace; drives the next interval via `I = -log(R) / log(0.9) × s`
- **Difficulty** (`d`) — intrinsic hardness of the card; modulates stability updates on review

---

## 7. Key Runtime Flows

### 7.1 Dependency Wiring

`lib/app/bootstrap_app.dart` constructs all services and repositories, wires callback hooks (`onDeckCreated`, `onDeckDeleted`), and exposes everything via `MultiProvider`. Critical services are set up synchronously; deferred services (notifications, enrichment queue) are initialized after the first frame.

### 7.2 Review Session

1. `FlashcardService.getFlashCardsForReview(deckId)` queries `flashcard_stats` for due cards.
2. Daily review limit is applied: `learning`/`relearning` cards are always included; `review`-state cards are capped by `maxReviewsPerDay − todayReviewCount`.
3. `FlashcardService.reviewCard(speciesId, deckId, grade)` invokes `FsrsService.reviewCard()`, increments `daily_counts`, and reschedules push notifications.

### 7.3 Enrichment Queue

After a deck is created/imported, `INatEnrichmentQueueService` runs staged background enrichment:
1. Download reference images for species
2. Fetch primary iNaturalist photos (via `entity_external_ids` or live API + `external_identifier_cache`)
3. Fetch common names → persist in `runtime_common_names` + update search projection
4. Photo backfill for remaining species

---

## 8. Important Distinctions

| Pair | Distinction |
|---|---|
| `sources` vs `metadata` | `sources` describes a data source for UI/attribution; `metadata` tracks technical import/version state |
| `entity_external_ids` vs `external_identifier_cache` | `entity_external_ids` is ETL-produced and ships with the app; `external_identifier_cache` is discovered at runtime |
| `pictures` vs `inat_photo_cache` | `pictures` are bundled reference images from the ETL; `inat_photo_cache` contains runtime-fetched iNaturalist photos |
| `deck_config.desired_retention` vs `UserPreferencesService.defaultDesiredRetention` | Per-deck override stored in SQLite; global fallback stored in SharedPreferences |

---

## 9. Related Docs

- ETL overview: [`etl/README.md`](../etl/README.md)
- ETL ↔ Flutter integration: [`etl/FLUTTER_INTEGRATION.md`](../etl/FLUTTER_INTEGRATION.md)
- Architecture improvement tasks: [`misc/tasks/architecture-improvements.md`](./tasks/architecture-improvements.md)
