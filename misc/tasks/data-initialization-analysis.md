# App Data Initialization — Analysis

## Current Workflow

```
FishBase Parquet files  →  DuckDB SQL scripts  →  aquaflash.db  →  Flutter asset  →  Device
(external, local)          (manual, in order)     (30 MB binary)    (bundled)          (copied on first launch)
```

1. **Parquet files** downloaded from FishBase (`v24.07`) and stored outside the repo
2. **7 DuckDB SQL scripts** (`misc/sql-scripts/`) are run manually in dependency order to populate a SQLite DB: classes → orders → families → genera → species → pictures → fts
3. The resulting **`assets/database/aquaflash.db`** (~30 MB) is committed to the repo and bundled as a Flutter asset
4. On **first app launch**, `DatabaseHelper` copies the asset byte-for-byte to the writable app data directory and opens it read-write
5. On **subsequent launches**, the existing local copy is opened directly (asset is ignored)
6. User data (decks, flashcard stats) is written into the **same database file** as the reference data

---

## Problems with the Current State

| # | Problem | Impact |
|---|---|---|
| 1 | **No update path for existing users** | Local DB is skipped if it already exists — users never receive updated species data after install |
| 2 | **Reference & user data share one file** | Replacing species data would destroy deck and flashcard progress |
| 3 | **Fragile migration** | Schema changes are a single hardcoded `ALTER TABLE` with a swallowed exception — not scalable |
| 4 | **30 MB binary in the bundle** | Bloats app download size on every platform |
| 5 | **ETL is manual and undocumented** | No runner script, no README; wrong execution order breaks FK constraints |
| 6 | **Hardcoded old project path in scripts** | Scripts point to `/aqua-flip/aqua_flash/...` instead of `/discere/...` |
| 7 | **Not reproducible** | Requires FishBase parquet files at a specific local path outside the repo |

---

## Option A: Two Databases

**Split into `aquaflash_reference.db` (read-only, bundled) and `aquaflash_user.db` (writable, created on first run).**

| | |
|---|---|
| ✅ | Clean lifecycle separation — reference DB can be replaced on each app update |
| ✅ | Reference DB opened read-only — no accidental writes |
| ✅ | User data will never be touched when shipping new species data |
| ✅ | Easier to test repositories in isolation |
| ❌ | Requires refactoring all repositories that currently share one `db` instance |
| ❌ | Cross-DB JOINs require SQLite `ATTACH` — more complex queries |
| ❌ | Two connection objects to manage and inject |

---

## Option B: Versioned Migration System

**Keep one DB but track a `schema_version` and conditionally re-import reference data on app update.**

| | |
|---|---|
| ✅ | Smaller refactor — repositories stay unchanged |
| ✅ | Single connection, no cross-DB query complexity |
| ✅ | Standard mobile pattern (sqflite `onUpgrade`) |
| ❌ | Doesn't solve the root problem — reference and user data still share one file |
| ❌ | Migration chains grow in complexity across versions |
| ❌ | A failed mid-migration can corrupt both reference and user data |
| ❌ | Bundled binary size problem remains |

---

## Recommendation

**Option A** is the stronger long-term architecture. The split correctly reflects the different data lifecycles. Cross-entity joins (species ↔ decks) are rare and typically resolved in the service layer, not at the SQL level, so the ATTACH complexity is manageable.

---

## Implementation Plan / Tasks

### Phase 1: Infrastructure & Database Helper
- [ ] Replace the bundled `aquaflash.db` asset with the new `discere_reference.db`.
- [ ] Refactor `DatabaseHelper` to implement the Two-Database Architecture:
  - Add logic to copy `discere_reference.db` on first launch.
  - Implement update mechanism checking the `metadata` table to replace the read-only DB on version changes.
  - Add initialization for `discere_user.db` to handle `decks` and `flashcard_stats` schemas.

### Phase 2: Refactor Reference Data Repositories
- [ ] Update `SpeciesRepository` and `SearchRepository` to use `DatabaseHelper.referenceDb` (read-only).
- [ ] Adopt the new FTS4 suffix/prefix search `MATCH ?` logic.
- [ ] Update `Species` and `Picture` models/mappers to handle the new schema fields (`id` as UUID, `external_id`, `external_source`).

### Phase 3: Refactor User Data Repositories
- [ ] Update `DeckRepository` and `FlashCardStatRepository` to use `DatabaseHelper.userDb` (read-write).
- [ ] Refactor `FlashCardStat` model to store `external_id` and `external_source` instead of a direct foreign key `species_id`.

### Phase 4: Service Layer & Migration
- [ ] Update `DeckService` and `FlashCardService` to fetch basic stats/decks from `userDb` and individually join/resolve the full Species details from `referenceDb`.
- [ ] Decide on user data migration: Implement a one-off migration from the old `aquaflash.db` to the new `discere_user.db`, OR clear the old database and start fresh if backwards compatibility is unnecessary.
