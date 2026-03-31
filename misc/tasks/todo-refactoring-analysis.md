# Discere App — Refactoring Analysis & Suggestions

A comprehensive review of the Discere Flutter codebase, with concrete suggestions for cleaner architecture and easier future development.

---

## 1. Extract Reusable Widgets from Pages

Several pages contain inline widget trees that should be standalone components.

- [ ] **1a. `_AddSpeciesSheet` → own file**
  - **Current**: Embedded inside `edit_deck_page.dart` (~200 lines).
  - **Suggestion**: Move to `lib/ui/components/add_species_sheet.dart`.

- [ ] **1b. `_SpeciesRow` → own file**
  - **Current**: Private widget inside `edit_deck_page.dart`.
  - **Suggestion**: Move to `lib/ui/components/species_row_tile.dart`.

- [ ] **1c. Watchlist species card → own file**
  - **Current**: Built inline in `watchlist_page.dart`.
  - **Suggestion**: Extract to `lib/ui/components/watchlist_species_card.dart`.

- [ ] **1d. Category filter tabs → own file**
  - **Current**: Built inline in `watchlist_page.dart`.
  - **Suggestion**: Extract to `lib/ui/components/category_filter_tabs.dart`.

- [ ] **1e. `_SectionLabel` → shared component**
  - **Current**: Private class in `create_deck_page.dart`.
  - **Suggestion**: Move to `lib/ui/components/section_label.dart`.

---

## 2. Eliminate Code Duplication Between Pages

- [x] **2a. Cover image picking logic (Create ↔ Edit)**
  - **Current**: Identical methods in both pages.
  - **Suggestion**: Create `CoverImagePickerMixin` or a `CoverImageController`.

---

## 3. Service Layer Refactoring

- [ ] **3a. `FavoriteService` + `WatchListService` → merge or abstract**
  - **Current**: Nearly identical functionality.
  - **Suggestion**: Merge into a generic `PreferenceSetService`.

- [x] **3b. `DecksService` God-service cleanup**
  - **Current**: Handles CRUD, Import, Seed Data, View assembly.
  - [x] Extract `ImportExportService` (located in `lib/service/common/`).
  - [ ] Extract Hardcoded seed data to `SeedDataService` or JSON assets.

- [ ] **3c. `ImageService` split**
  - **Current**: Handles both species photo downloads and cover image management.
  - **Suggestion**: Split into `SpeciesImageService` and `CoverImageService`.

- [x] **3d. `FlashCardService._getFlashCardStat()` bug**
  - **Current**: Creates fresh stats, SM2 never accumulates progress.
  - **Status**: [X] Fixed core logic (Repository lookup + Async methods).

---

## 4. Global Configuration & Constants

- [ ] **4a. App-wide constants file**
  - **Suggestion**: Create `lib/config/app_constants.dart` for App Name, User-Agent, dir names, etc.

- [ ] **4b. Centralize notification strings**
  - **Suggestion**: Localize strings in `FlashCardService`.

- [ ] **4c. Centralize `SharedPreferences` keys**
  - **Suggestion**: Create `lib/config/prefs_keys.dart`.

---

## 5. Dependency Injection Improvements

- [ ] **5a. `main.dart` `setupServices()` restructuring**
  - **Suggestion**: Group registrations into helper methods.

- [ ] **5b. `SearchRepository` UI exposure**
  - **Suggestion**: Wrap in `SearchService` instead of exposing Repo to UI.

---

## 6. Hardcoded & Non-Localized Strings

- [x] **6a. German strings in `watchlist_page.dart`**
  - **Suggestion**: Move to `context.loc.*`.

- [x] **6b. Mock conservation status in `watchlist_page.dart`**
  - **Suggestion**: Remove placeholder logic/fake data.

---

## 7. Architecture & Pattern Improvements

- [ ] **7a. `SpeciesRepository` SQL duplication**
  - **Suggestion**: Extract a shared base query builder method.

- [ ] **7b. Theme organization**
  - **Suggestion**: Remove empty/unused themes.

- [ ] **7c. `AppHttpOverrides` cleanup**
  - **Suggestion**: Move to `lib/config/http_config.dart`.

---

## 8. Project Hygiene

- [ ] **8a. Clean up log files in project root**
  - **Suggestion**: Add to `.gitignore`, delete existing logs (~100MB).

- [ ] **8b. Empty/unused files**
  - **Suggestion**: Delete `app_theme.dart` and `search_result.dart`.

---

## Prioritized Roadmap

| Status | Priority | Area | Impact | Effort |
|---|---|---|---|---|
| [x] | 🔴 High | Fix `_getFlashCardStat` bug (#3d) | Critical logic | Low |
| [x] | 🔴 High | Remove hardcoded German strings (#6a) | i18n | Low |
| [x] | 🔴 High | Remove mock conservation status (#6b) | Data integrity | Low |
| [x] | 🟡 Medium | Extract import/export from `DecksService` (#3b) | Architecture | Low |
| [x] | 🟡 Medium | Deduplicate cover-image logic (#2a) | DRY | Medium |
| [ ] | 🟡 Medium | Merge `FavoriteService`/`WatchListService` (#3a) | DRY | Low |
| [ ] | 🟡 Medium | Create `app_constants.dart` (#4a) | Maintenance | Low |
| [ ] | 🟡 Medium | Extract reusable widgets (#1) | Clean code | Medium |
| [ ] | 🟢 Low | Split services layer (#3c, #3b) | SRP | Medium |
| [ ] | 🟢 Low | Refactor `SpeciesRepository` SQL (#7a) | Performance | Medium |
| [ ] | 🟢 Low | Project Hygiene (#8) | Cleanliness | Low |
