# Discere

Discere is a Flutter-based flashcard application designed to help users learn and memorize information effectively.

## Developer Setup

To get started with the project, please follow the steps below after cloning the repository.

### 1. Prerequisites

Ensure you have a complete Flutter development environment set up. You can verify your setup by running:

```sh
flutter doctor -v
```

### 2. Get Dependencies

Download all the project's dependencies by running the following command from the root of the project:

```sh
flutter pub get
```

### 3. Generate Localization Files

The project uses code generation for localization. To generate the necessary files, run:

```sh
flutter gen-l10n
```

### 4. Generate Code for Serializable Models

The project also uses code generation for JSON serialization. Run the following command to generate the required files:

```sh
dart run build_runner build --delete-conflicting-outputs
```

### 5. Generate Assets (Optional)

If the splash screen or launcher icons need to be updated:

#### Splash Screen
```sh
# Regenerate splash screen assets
dart run flutter_native_splash:create
```

#### Launcher Icons
```sh
# Regenerate launcher icons
dart run flutter_launcher_icons
```

### 6. Run the Application

Once the setup is complete, you can run the application on a connected device or simulator:

```sh
flutter run
```

## Developer / Architecture

Discere uses a two-database architecture:

- `discere_reference.db`
  - read-only
  - built by the ETL and shipped as an app asset
  - contains taxonomy, species, reference pictures, source metadata, and offline external-ID mappings
- `discere_user.db`
  - read-write
  - created locally on the device
  - contains decks, flashcard progress, and all runtime caches

### High-Level Data Flow

1. The ETL imports FishBase / SeaLifeBase data and builds `discere_reference.db`.
2. On app startup, the reference DB asset is copied into app storage if needed.
3. The app reads taxonomy/species/reference pictures from the reference DB.
4. User-specific state such as decks, review progress, iNaturalist caches, and runtime common names lives in the user DB.
5. iNaturalist enrichment runs on top of the reference data:
   - first via offline mappings from `entity_external_ids`
   - then via runtime fallback caches in the user DB

### Main Tables

#### Reference DB

- `species`, `genera`, `families`, `orders`, `classes`
  - the core biological entities shown by the app
  - produced by the ETL
  - these tables form the canonical biological backbone of the app
  - all flashcards, watchlist entries, taxonomy detail pages, and most search results ultimately refer back to these entities
  - they are intentionally stable and read-only at runtime, so user progress can safely reference them via IDs

- `pictures`
  - reference images bundled with the reference DB
  - stores source/origin/license information used by the app
  - this is the app's built-in image inventory from curated upstream sources such as FishBase / SeaLifeBase
  - these images are the first source of truth for local image coverage because they do not require network access at runtime
  - the app uses the table not only for URLs/paths, but also for attribution and license filtering

- `sources`
  - describes upstream data sources
  - used for attribution, citation, licensing, and source-related UI
  - examples: FishBase, SeaLifeBase
  - think of this as the "source catalog" of the reference DB
  - it does not store species data itself; instead it explains where the imported data came from and how that source should be presented
  - this is important for transparency in the UI, legal attribution, and future source-specific features

- `metadata`
  - simple key/value import metadata
  - used to track which source or enrichment version is inside the shipped reference DB
  - examples:
    - `fishbase -> v25.07`
    - `sealifebase -> v25.07`
    - `inaturalist_enrichment -> 2026-04-08`
  - this table is purely technical and intentionally minimal
  - unlike `sources`, it is not meant for user-facing descriptions; it is mainly used to answer operational questions such as:
    - which ETL import version was bundled into the current app asset?
    - did a specific enrichment step already run?
    - should the local copy of the reference DB be refreshed?

- `entity_external_ids`
  - offline mapping table from Discere entities to external systems
  - current main use: mapping Discere species and taxonomy keys to iNaturalist taxon IDs
  - this is the preferred source for external IDs at runtime
  - may contain real entity IDs such as `discere:fishbase_species:1450`
  - may also contain normalized taxonomy keys such as `genus:barbus`
  - this table is the bridge between Discere's internal IDs and third-party systems
  - it exists so the app can resolve external identifiers without hitting remote APIs during normal operation
  - for the current iNaturalist flow, this table is the critical offline accelerator:
    - species can be mapped directly to iNat taxon IDs
    - taxonomy name keys such as `family:cyprinidae` can also be mapped for common-name enrichment
  - if a mapping exists here, runtime code should prefer it over a live API resolve

#### User DB

- `decks`
  - the user's local decks
  - stores only user-created or imported deck metadata such as name, description, cover image path, and language
  - species membership is not stored directly here; that is derived via `flashcard_stats`
  - this separation allows deck metadata and study progress to evolve independently

- `flashcard_stats`
  - spaced-repetition progress per species per deck
  - this is the main learning-state table of the app
  - every row ties one species to one deck and stores FSRS review state such as interval, repetition, next review date, and stability/difficulty values
  - in practice this table defines:
    - which species belong to a deck
    - which cards are due
    - how far the user has progressed in that deck

- `external_identifier_cache`
  - runtime fallback cache for external IDs discovered live
  - used when `entity_external_ids` has no mapping yet
  - example: a species was resolved live against iNaturalist and the result is cached locally
  - this table is intentionally opportunistic, not authoritative
  - it exists because the shipped reference DB cannot contain every mapping forever, and some IDs are only discovered while the user is actively importing or browsing
  - typical flow:
    - app checks `entity_external_ids` in the reference DB
    - if nothing is found, app resolves the ID live
    - successful result is written into `external_identifier_cache`
    - later runs reuse the cached value and avoid another resolve

- `inat_photo_cache`
  - local cache of fetched iNaturalist photo metadata per species
  - prevents repeated photo requests to iNaturalist
  - this table stores the runtime results of iNaturalist photo enrichment
  - rows include photo URL, thumbnail URL, attribution, license code, and fetch timestamp
  - it allows the app to treat downloaded iNat photos almost like local reference data on subsequent loads
  - important distinction:
    - `pictures` = shipped, curated reference images
    - `inat_photo_cache` = runtime-enriched images discovered later

- `runtime_common_names`
  - generic local cache of runtime-fetched common names
  - stores both:
    - species common names using keys like `species:<discere species id>`
    - taxonomy common names using keys like `genus:barbus` or `family:cyprinidae`
  - this replaced the previous split between separate species and taxonomy iNat name tables
  - the goal is to keep the runtime enrichment layer simpler and more uniform:
    - one table
    - one repository
    - one lookup pattern based on `entity_key`
  - it prevents repeated iNaturalist requests for both species-level and taxonomy-level common names
  - this is the canonical runtime name table in the user DB

- `runtime_common_name_search_documents`
  - local search projection built from `runtime_common_names`
  - makes newly fetched common names searchable without rebuilding the reference DB
  - each row stores the searchable scientific name plus the currently known common names per language for one `entity_key`
  - when the app fetches new common names from iNaturalist, those names are projected into this table so search results improve immediately
  - without this table, the names would exist in `runtime_common_names` but would not automatically become discoverable through the app's local search

- `runtime_common_name_search_fts`
  - FTS index for `runtime_common_name_search_documents`
  - optimized for local prefix/full-text lookup during search
  - this keeps the runtime common-name cache queryable without touching the read-only reference DB

### Module Structure

The Flutter app is no longer organized by global technical layers such as
`model/`, `service/`, or `ui/`. Instead it is split into a small set of
modules with explicit dependency rules.

- `shared/`
  - generic infrastructure and cross-cutting helpers
  - responsibility:
    - owns technical building blocks that are not tied to a single business module
    - provides reusable infrastructure for storage, networking, logging, localization, and low-level UI primitives
    - must remain domain-agnostic and must not import `catalog`, `enrichment`, `application`, `learning`, or `app`
  - does not own:
    - species, taxonomy, search, deck, review, or enrichment workflows
  - examples:
    - `DatabaseHelper`
    - `ImageService`
    - `LanguageService`
    - `DebugLog`
    - generic UI primitives and utilities
    - external infrastructure such as `WikiService` and `INaturalistService`

- `catalog/`
  - the reference catalog domain
  - responsibility:
    - owns the app's canonical reference entities and catalog-facing use cases
    - contains species, taxonomy, search, source metadata, and catalog-specific presentation code
    - is the home of read models and UI for browsing the biological catalog
    - may use `shared`, but must not orchestrate enrichment or application workflows itself
  - does not own:
    - remote fetching, background enrichment, or cross-module orchestration
  - examples:
    - species detail
    - taxonomy detail
    - search repository and search UI
    - watchlist
    - local image resolution for already-known `Picture` objects

- `enrichment/`
  - runtime enrichment on top of the reference catalog
  - responsibility:
    - fetches, caches, and persists runtime data that extends the catalog
    - integrates with external systems such as iNaturalist
    - translates external payloads into catalog-compatible models and cache records
    - owns enrichment queues and post-import enrichment workflows
  - does not own:
    - catalog UI, deck/review logic, or cross-module page composition
  - examples:
    - iNaturalist photo lookup
    - runtime common-name fetching
    - external ID fallback resolution
    - enrichment queueing and staged backfills

- `application/`
  - orchestration layer for workflows that span multiple modules
  - responsibility:
    - coordinates multi-step workflows that combine services from other modules
    - hides orchestration from feature modules that should stay focused on their own domain
    - returns higher-level results that are ready to be consumed by `learning` or `app`
  - does not own:
    - canonical catalog models, external API clients, or learning-state persistence
  - example:
    - `SpeciesMediaService`, which coordinates enrichment-side photo lookup with catalog-side local image resolution

- `learning/`
  - decks, flashcards, spaced repetition, import/export, and review flows
  - responsibility:
    - owns the study experience: decks, flashcards, spaced repetition, import/export, review sessions, and related UI
    - may consume `catalog`, `enrichment`, and `application` to support learning flows
    - owns learning-state repositories and services such as deck CRUD and review progress
  - does not own:
    - catalog-wide reference data, enrichment pipelines, or general-purpose orchestration outside learning

- `app/`
  - composition root and shell
  - responsibility:
    - wires the application together at runtime
    - owns provider setup, navigation, route-level loaders, and shell screens
    - is allowed to compose multiple modules and trigger higher-level flows for navigation
  - does not own:
    - reusable feature logic that belongs in `catalog`, `learning`, `enrichment`, or `application`

### Module Dependency Rules

These rules are enforced by `test/architecture/module_dependency_test.dart`.

- `shared -> (nothing)`
- `catalog -> shared`
- `enrichment -> catalog, shared`
- `application -> catalog, enrichment, shared`
- `learning -> catalog, enrichment, application, shared`
- `app -> shared, catalog, enrichment, application, learning`

Practical implications:

- `shared` must not import any feature module
- `catalog` must not import `enrichment` or `application`
- cross-module orchestration belongs in `application` or `app`, not in `catalog`
- reusable catalog-specific building blocks belong in `catalog/common`, not in `shared`

### Runtime Responsibilities

- `lib/main.dart`
  - composition root for Provider wiring
  - instantiates repositories and services and connects module boundaries

- `shared/persistence/database_helper.dart`
  - opens the reference DB and user DB
  - copies the reference DB asset into local storage
  - creates and migrates the user DB schema

- `application/species_media/species_media_service.dart`
  - orchestrates species media loading across modules
  - combines:
    - `enrichment/service/species_photo_service.dart`
    - `catalog/service/local_species_image_service.dart`
  - returns `SpeciesWithLocalImages` for higher-level flows

- `catalog/service/local_species_image_service.dart`
  - resolves existing `Picture` objects to local file paths
  - does not care whether the picture originated from FishBase, SeaLifeBase, or iNaturalist

- `enrichment/service/species_photo_service.dart`
  - resolves runtime species photos
  - reads iNaturalist photo cache
  - optionally fetches live iNaturalist photos
  - writes photo metadata back into the user DB cache

- `enrichment/service/enrichment_service.dart`
  - owns post-import enrichment flows
  - downloads reference images
  - fetches iNaturalist photos and common names
  - persists runtime common names and updates the runtime search projection

- `enrichment/service/inat_enrichment_queue_service.dart`
  - background queue for staged enrichment
  - runs enrichment in phases:
    - reference images
    - primary iNaturalist photos
    - common names
    - photo backfill

- `catalog/repository/runtime_common_name_search_repository.dart`
  - owns the runtime search projection for fetched common names
  - makes runtime common names immediately searchable without rebuilding the reference DB

### Important Distinctions

- `sources` vs `metadata`
  - `sources` describes a source for UI and attribution
  - `metadata` tracks technical import/version state

- `entity_external_ids` vs `external_identifier_cache`
  - `entity_external_ids` is the ETL-produced, offline, authoritative mapping shipped with the app
  - `external_identifier_cache` is the user-DB fallback for IDs discovered at runtime

- `pictures` vs `inat_photo_cache`
  - `pictures` contains bundled reference pictures from the ETL
  - `inat_photo_cache` contains runtime-fetched iNaturalist photos

### Related Docs

- ETL overview: [`etl/README.md`](/Users/fabian/projekte/discere/etl/README.md)
- Flutter + DB integration details: [`etl/FLUTTER_INTEGRATION.md`](/Users/fabian/projekte/discere/etl/FLUTTER_INTEGRATION.md)
