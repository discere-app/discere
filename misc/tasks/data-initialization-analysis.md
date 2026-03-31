# App Data Initialization — Current Architecture Analysis

## Current Workflow (Two-Database Architecture)

```
FishBase Parquet files  →  DuckDB/sqlite3 ETL  →  discere_reference.db  →  Flutter asset  →  Device
(external, HF)             (etl/build.sh)         (binary, Reference)      (bundled)          (copied/updated via metadata)
```

1. **ETL Pipeline**: Data is ingested via `etl/build.sh`, which downloads Parquet files, uses DuckDB to process them, and generates deterministic UUIDs (v5 style via MD5).
2. **Reference Database**: The output is `assets/database/discere_reference.db` (~15-30 MB), a read-only SQLite database bundled with the app containing taxonomy and images.
3. **App Initialization (`DatabaseHelper`)**:
    - **Reference DB (`discere_reference.db`)**: On launch, the app checks the `metadata` table in the bundled asset against the local copy in the app's document directory. If the asset has a newer or different version (e.g., `fishbase=v25.04`), it overwrites the local copy. This database is opened **read-only**.
    - **User DB (`discere_user.db`)**: A separate read-write database is created dynamically using sqflite's `onCreate`. This stores user-generated content like `decks` and `flashcard_stats`.
4. **Stable External Identifiers**: The ETL generates stable UUIDs based on the external source and ID (e.g., `discere:fishbase:12345`). Because these UUIDs are deterministic, user progress stored in `discere_user.db` remains perfectly linked to `discere_reference.db` even when the reference database is completely regenerated and replaced.

---

## Resolved Architectural Problems

The original monolithic `aquaflash.db` architecture had several critical flaws that have now been resolved by the Two-Database approach:

| # | Previous Problem | Resolution |
|---|---|---|
| 1 | **No update path for existing users** | The `DatabaseHelper` now compares the `metadata` table of the bundled asset vs. the local copy, allowing automated, safe replacement of reference data on app updates. |
| 2 | **Reference & user data share one file** | Strict separation. Replacing `discere_reference.db` has zero impact on `discere_user.db` (decks and flashcard progress). |
| 3 | **Fragile migration** | User data schema uses standard `sqflite` migrations (`onUpgrade`). Reference data relies on complete file replacement, so no SQL schema migrations are needed for taxonomy data. |
| 4 | **ETL was manual and undocumented** | Replaced with a fully automated, documented script (`etl/build.sh`) using DuckDB and SQLite. |
| 5 | **UUID loss during DB rebuilds** | The ETL now generates **deterministic UUIDs** using DuckDB's `md5()`. We no longer need to track `external_id` / `external_source` in the app's user database because the internal UUIDs never change between ETL runs. |

---

## Technical Learnings & Best Practices Validated

- **FTS4 over FTS5:** Using SQLite FTS4 on mobile avoids the inconsistency of FTS5 availability across different iOS/Android SQLite builds.
- **Cross-Database Joins vs Service Layer Assembly:** Instead of complex SQL `ATTACH DATABASE` statements, the cross-database logic is cleanly handled in the Flutter Service layer (e.g., `DeckService`, `FlashCardService`). The repositories simply fetch the UUIDs from `userDb` and then batch-query the full models from `referenceDb`.
- **Dart Model Cleanliness:** Because the ETL guarantees stable UUIDs, the `FlashCardStat` Dart model does not need to be polluted with `external_id` and `external_source`. The app relies entirely on the primary `species_id`.

---

## Implementation Plan / Tasks

All tasks for this migration have been completed:

### Phase 1: Infrastructure & Database Helper
- [x] Replace the bundled `aquaflash.db` asset with the new `discere_reference.db`.
- [x] Refactor `DatabaseHelper` to implement the Two-Database Architecture:
  - Add logic to copy `discere_reference.db` on first launch.
  - Implement update mechanism checking the `metadata` table to replace the read-only DB on version changes.
  - Add initialization for `discere_user.db` to handle `decks` and `flashcard_stats` schemas.

### Phase 2: Refactor Reference Data Repositories
- [x] Update `SpeciesRepository` and `SearchRepository` to use `DatabaseHelper.referenceDb` (read-only).
- [x] Adopt the new FTS4 suffix/prefix search `MATCH ?` logic.
- [x] Update `Species` and `Picture` models/mappers to handle the new schema fields (`id` as UUID, `external_id`, `external_source`).

### Phase 3: Refactor User Data Repositories
- [x] Update `DeckRepository` and `FlashCardStatRepository` to use `DatabaseHelper.userDb` (read-write).
- [x] Refactor `FlashCardStat` model. *(Note: Initially planned to store external_id to link databases. Ultimately resolved by implementing deterministic UUIDs in the ETL instead, keeping the Dart model and user schema cleaner).*

### Phase 4: Service Layer & Migration
- [x] Update `DeckService` and `FlashCardService` to fetch basic stats/decks from `userDb` and individually join/resolve the full Species details from `referenceDb`.
- [x] Decide on user data migration. *(Decided: NO backwards migration needed, starting fresh)*.

---

## Next Steps / Future Improvements

While the core Two-Database architecture is functioning reliably, the following improvements should be considered for future production readiness:

### 1. Remote Database Download (Reduce App Bundle Size) [Priority: Medium]
Currently, `discere_reference.db` is bundled within `assets/database/`, which permanently bloats the app download size (15-30 MB and growing as more sources are added).
* **Improvement**: Host the pre-built `discere_reference.db` on a remote server (e.g., GitHub Releases, AWS S3, or Firebase Storage). On first launch, the app downloads the database. Updates can be triggered by checking a remote `versions.json`.

### 2. Soft-Delete (`status` field) in ETL [Priority: High]
Currently, the ETL script clears all existing data before importing new parquets (`DELETE FROM species`). If the external source (e.g., FishBase) removes a species, that species disappears from our DB.
* **Problem**: User progress in `discere_user.db` will point to a dangling, non-existent `species_id`.
* **Improvement**: Add a `status` column (`active`, `deprecated`) to the taxonomy schema. The ETL should compare new data against existing data and mark missing entities as `deprecated` rather than physically deleting them.

### 3. User Database Migration Framework [Priority: High]
The `_upgradeUserSchema` in `DatabaseHelper` now implements a sequential migration system.
* [x] **Improvement**: Implement a robust migration system (e.g., iterating through a list of SQL scripts based on `oldVersion` vs `newVersion`) to safely evolve `decks` and `flashcard_stats` schemas gracefully when users update the app.

### 4. ETL CI/CD Pipeline [Priority: Low]
The reference database generation is still executed manually by the developer locally.
* **Improvement**: Automate the ETL process using GitHub Actions. A scheduled workflow (or trigger) could run `etl/build.sh`, validate the row counts, and automatically create a new GitHub Release containing the freshly baked `discere_reference.db` asset.
