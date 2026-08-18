# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Discere** is a Flutter flashcard learning app for studying biological species (primarily marine life). Users create decks of species cards and review them using the FSRS 6 spaced-repetition algorithm.

## Common Commands

```bash
# Install dependencies
flutter pub get

# Generate localization files (required after changing l10n/*.arb files)
flutter gen-l10n

# Run code generation (required after changing models with @JsonSerializable or adding new mocks)
dart run build_runner build --delete-conflicting-outputs

# Run the app
flutter run

# Run all unit tests
flutter test

# Run a single test file
flutter test test/learning/service/decks_service_test.dart

# Run the architecture dependency tests (enforces the module boundaries below)
flutter test test/architecture/

# Run integration tests
flutter test integration_test/

# Lint
flutter analyze
```

## Commit Messages

Never add AI attribution to commit messages — no `Co-Authored-By: Claude …`, no "Generated with Claude Code", nothing similar. A commit message contains only the description of the change.

Keep commit messages short and focused on the functional/domain-level change (what changed and why, from a product/architecture perspective). Do not report mechanical details like line counts, line numbers, or file-by-file diff stats — that's what `git diff`/`git log --stat` are for.

## What's New

`distribution/whatsnew/{de-DE,en-US}/whatsnew` are flat, append-only Play Store "recent changes" changelogs — one line per entry, in both locales, prefixed `Neu:`/`Fix:`/`Änderung:` (`New:`/`Fix:`/`Change:` in English). They aren't reset per release, so entries accumulate across versions until manually pruned around a version bump.

Before opening or merging a PR, check whether it contains a user-facing change (new feature, a fix a user would actually notice, a UX change) as opposed to a pure refactor, internal cleanup, or dev/CI-only change. If it does, add one matching line to both locale files — this is easy to forget once the change itself is already reviewed and merged, so check it explicitly rather than assuming it was done alongside the code change. A PR that bundles multiple distinct user-facing changes (e.g. two unrelated features landed together) gets one line per change, not one line per PR.

## Documentation

Docs (`docs/`, `CLAUDE.md`, module READMEs) describe only the current state and known open problems — not history. No "was X, now Y", no "this replaced the old …", no "bug fixed in …" narratives; justify the current design from current reasoning. Past states, migrations, and the motivation-by-diff belong in the git history, not the docs. The only exception is when the current behavior can't be understood without it (e.g. a migration-step comment) or the user explicitly asks for history/rationale to be written down.

## In-App Tutorials

Four first-run coach-mark tours (`tutorial_coach_mark`) walk users through UI that isn't obvious from its icon alone: `lib/app/main_screen_tutorial.dart` (`MainScreenTutorial` — deck favorite action, deck edit action, watchlist tab), `lib/catalog/species_detail/species_detail_tutorial.dart` (`SpeciesDetailTutorial` — add-to-deck action), `lib/learning/decks/edit/edit_deck_tutorial.dart` (`EditDeckTutorial` — the learning settings section, where learning mode/name type/review mode are changed), and the inline tutorial in `lib/learning/flashcard/deck_page.dart` (`_showFlashcardTutorial` — flip card, rating buttons or multiple-choice option picker depending on review mode, watchlist button during review; the intro step also notes when the deck's learning mode asks for a genus/family name rather than a species name). Their copy lives in the `tutorial*` keys in `lib/l10n/*.arb`.

After any change to app behavior that one of these targets or describes — a button moved, renamed, removed, or its `GlobalKey` dropped; a flow that now works differently — check whether the affected tutorial still points at a real target and whether its description still matches what the user actually sees, and update it if not. A stale `GlobalKey` target throws at runtime; a stale description just quietly misleads new users.

Adding a *step* to an existing multi-step tour (e.g. `MainScreenTutorial`'s `deckEdit` step, added after its original two-step `hasSeenTutorial`-gated tour) needs its own `hasSeen*` flag, checked independently of the tour's original flag — otherwise a user who already dismissed the tour before the new step existed will never see it, since the whole tour is gated behind one flag they already flipped. See `hasSeenDeckEditTutorial` / `MainScreenTutorial.includePreviouslySeenSteps` for the pattern: show only the new step (no re-announcing intro, no replaying already-seen steps) when the original flag is already set.

## Architecture

The app is organized as **feature-based vertical slices** under `lib/`, not a horizontal ui/service/persistence split. Each slice owns its own models, repositories, services, and widgets. A one-directional dependency matrix between slices is enforced automatically by `test/architecture/module_dependency_test.dart` (via `dart_arch_test`) — run `flutter test test/architecture/` after moving code between slices:

```
shared        → (nothing from discere — dependency-free foundation)
external      → shared
diagnostics   → shared
catalog       → external, shared
enrichment    → catalog, external, diagnostics, shared
learning      → catalog, enrichment, external, shared
app           → catalog, enrichment, external, diagnostics, learning, shared
```

`lib/theme/` and `lib/l10n/` are infrastructure and sit outside this graph — implicitly importable from anywhere.

Within a slice, the common pattern is `page` (StatefulWidget) → `presenter` → `view_model`, with a separate `repository/` doing raw SQL and a `service/` for business logic. Derived-state logic (dirty-tracking, review-mode validity, result merging, label/icon mapping for an enum) belongs in a small presenter class next to the widget, not inline in `State` — see `learning/decks/edit_deck_presenter.dart`, `learning/flashcard/deck_session_presenter.dart`, `catalog/search/search_results_presenter.dart`, `learning/decks/learning_mode_style.dart` for the pattern. Not everything has been extracted this way yet — check the specific file first before assuming it has a presenter.

Once a page's file accumulates several large, self-contained private widgets — alternate full-screen states, dialogs, sections — split each into its own file in the same directory, one file per widget, with the class made public (no leading `_`) even though it's only used from one place. See `learning/flashcard/`, `learning/decks/edit/`, and `app/bootstrap/` for the pattern. This is orthogonal to the presenter pattern above, not a replacement for it — a presenter holds pure derived-state computation, not async orchestration coupled to `BuildContext`/`setState`/`mounted`, which stays directly in the State class regardless of size. See [`docs/architecture-overview.md`](docs/architecture-overview.md) §2 ("Widget organization") for the fuller rationale and more examples.

### Dependency Injection

Services and repositories are constructed once and wired via Provider in `lib/app/bootstrap/bootstrap_app.dart` (`_setupCriticalServices()`), which returns the `List<SingleChildWidget>` passed to the root `MultiProvider`. The actual per-slice construction lives in `lib/app/wiring/{catalog,learning,enrichment}_wiring.dart` — `bootstrap_app.dart` itself only orchestrates the setup sequence (splash/timeout/retry, the order dependencies must be built in) and assembles the provider list. `lib/main.dart` only sets up the Flutter binding/splash screen and calls `runApp(BootstrapApp(...))`. Services are injected via required constructor parameters (no hidden `?? Default()` fallbacks for stateful/IO collaborators — see `enrichment_wiring.dart` for the pattern); observable services use `ChangeNotifierProvider.value()`, stateless ones use `Provider.value()`. Cross-slice dependencies that would violate the matrix above are inverted with a port interface plus local adapter classes, constructed in the relevant wiring file — see `_DeckSpeciesSnapshotAdapter` and friends in `enrichment_wiring.dart` (enrichment→learning) and `DiagnosticsSink`/`LocalDiagnostics` in `shared/service/diagnostics_sink.dart` / `diagnostics/service/local_diagnostics.dart` (shared→diagnostics, needed because `LoggingHttpClient` lives in `shared` but the diagnostics implementation sits above it).

### Dual-Database Design

The app maintains two separate SQLite databases:

- **`discere_reference.db`** – Read-only. Contains species taxonomy data generated by the ETL pipeline (`etl/`). Never written to at runtime. **Not bundled in the app** (it outgrew the app bundle at ~400MB) — downloaded at runtime by `lib/shared/persistence/reference_database_provisioner.dart` from a small `manifest.json` (version, schema version, download URL, checksum) hosted alongside the deck data in `discere-data`. `bootstrap_app.dart` gates app startup on this: if a local copy already exists it's used immediately (with a silent background update check); on first launch / cleared app data it shows a blocking download screen instead. See [GitHub issue #54](https://github.com/discere-app/discere/issues/54) for the full design and `etl/FLUTTER_INTEGRATION.md` for the integration walkthrough.
- **`discere_user.db`** – Read-write, stored in app documents directory. Contains user decks, flashcard review stats, and runtime-cached data (e.g. enrichment job state, runtime common names).

Both are opened via the static singleton `lib/shared/persistence/database_helper.dart`, which only opens whatever file already exists at the expected path — provisioning the reference DB is `ReferenceDatabaseProvisioner`'s job, not `DatabaseHelper`'s.

### Key Directories

- `lib/shared/` – Dependency-free foundation: `persistence/` (`DatabaseHelper`), cross-cutting services (notifications, preferences, network availability, logging, image handling), and generic utils. Keep it that way — anything domain-specific (a notification payload shaped around one feature's model, a formatter with only one consumer) belongs in the slice that owns it, not here, even if that means a small generic primitive here plus a thin feature-specific wrapper above it (see `HostCooldownTracker`, a generic per-host failure/cooldown tracker fed by `LoggingHttpClient`, vs. the enrichment-specific notification title/body computation in `enrichment/queue/service/inat_enrichment_queue_service.dart`'s `_syncBackgroundNotificationContent`, which feeds `EnrichmentForegroundServiceKeeper`).
- `lib/external/` – HTTP clients for third-party APIs, one subfolder per provider (`inaturalist/` with the client and its response models). Depends only on `shared`; knows nothing about the app's domain slices. New external services get their own subfolder here.
- `lib/diagnostics/` – Local, on-device diagnostics: structured event/telemetry recording and HTTP-failure logging (`service/local_diagnostics.dart`), its SQLite-backed storage (`repository/`), and the `Logger` persistence toggle (`service/log_diagnostics_persistence.dart`). `shared/util/logging_http_client.dart` (which lives below this module) depends only on the `DiagnosticsSink` port in `shared/service/diagnostics_sink.dart`, implemented by `LocalDiagnostics` here. Enrichment-specific diagnostics config (`configureEnrichmentCompletionSummary`) stays in `enrichment/queue/service/enrichment_completion_diagnostics_persistence.dart` rather than here — it's a feature-specific wrapper, not a generic diagnostics primitive.
- `lib/catalog/` – Species/taxonomy catalog: search, species detail, taxonomy detail, watchlist. `repository/` (raw SQL against both DBs), `service/`, plus `search/`, `species_detail/`, `taxonomy_detail/`, `common/taxon_identity|taxon_classification/`.
- `lib/enrichment/` – Producer-consumer background pipeline that fetches and caches species photos and common names from iNaturalist. Four feature-based subfolders: `queue/` (deck-level job tracking/orchestration/UI-facing status — `INatEnrichmentQueueService`, the remaining single-stage `CoverJobRunner`/`EnrichmentJobRepository` for the deck cover image), `pipeline/` (the species-level work queue and its two independently-scheduled workers — `BaseWorker` for reference images, `INatWorker` as the single rate-limited iNaturalist consumer — plus `EnrichmentWorkRepository` and the actual fetch services), `media/` (on-demand species-image display via `SpeciesMediaService`, unrelated to the background queue), `ports/` (shared cross-cutting port interfaces). Runs entirely in the UI isolate, kept alive on Android by `EnrichmentForegroundServiceKeeper`'s foreground-service notification; `lib/app/background/inat_background_task.dart` is now only a no-op Workmanager callback for wakeups scheduled by old app versions. See [`docs/enrichment.md`](docs/enrichment.md) for the full architecture (worker responsibilities, retry/resume state machine, consent model, cross-deck dedup). Also owns `media/service/species_media_service.dart`, the composition point over `catalog` (species/images) used by `learning` and `app`.
- `lib/learning/` – Core flashcard/deck feature: `decks/`, `flashcard/` (review UI, FSRS 6 grading, multiple-choice/genus/common-vs-scientific-name review modes), `repository/`, `service/` (`DecksService`, `FlashcardService`, `FsrsService`), `model/`, plus import/export and sharing.
- `lib/app/` – Composition root: `bootstrap/` (`bootstrap_app.dart`'s setup orchestration plus its full-screen states) + `wiring/` (per-slice DI wiring), top-level pages (`main_screen_page.dart`, `settings_page.dart`, etc.), background task entrypoints.
- `lib/l10n/` – ARB localization files (DE, EN primary; FR, ES stubs)
- `etl/` – Standalone bash/duckdb/sqlite pipeline that builds `discere_reference.db` from fishbase/sealifebase data sources, plus `publish_release.sh` (publishes a built DB as a versioned release + manifest) and `scripts/build_test_fixture.sh` (filters a built DB down to the small curated fixture used by tests)

### State Management Patterns

- `Consumer<T>` / `Provider.of<T>()` for reactive UI updates
- `FutureBuilder` for one-shot async data loads
- `setState()` after navigation returns to force re-fetch
- `ChangeNotifier` for services that drive UI rebuilds (`DecksService`)
- Presenter/view_model classes (see `catalog/`) for screens with non-trivial derived state, decoupled from the widget for testability

### Code Generation

Three generated outputs — all require running `build_runner` or `gen-l10n` after changes:

1. `*.g.dart` files – JSON serialization via `json_serializable`
2. `test/*/mocks.dart` files – Test mocks via `mockito` (configured in `build.yaml`)
3. `lib/l10n/app_localizations*.dart` – Localization (via `flutter gen-l10n`)

### Model Serialization

Two conventions, by data source:

- **JSON/API models** (`BaseDeck`, `CreateDeck`, `SearchResult`, ...) use `json_serializable` (`@JsonSerializable()` + generated `fromJson`/`toJson`).
- **Models built from a single SQL row** (`Picture`, `FlashcardStat`, `DeckConfig`, `LocalePlaceMapping`, ...) get a `factory X.fromMap(Map<String, dynamic> map)` (and `toMap()` where the model is also written back) directly on the model — not a private mapper method living in the repository. `Picture` has two such factories (`fromMap` for the FishBase/SeaLifeBase `pictures` table, `fromINatCacheRow` for the differently-shaped `inat_photo_cache` table); pick a distinct factory name per source shape rather than overloading `fromMap`.

Models assembled by a repository from **multiple queries/joins** (`Species`, `Classification`, `TaxonomyDetail`, `EnrichmentJobRecord`) are a different concern — that's result-assembly, not row deserialization, so it stays as repository logic rather than a model factory.

### Error Messages & Localization

All user-facing text goes through `AppLocalizations` (`context.loc.*`, generated from `lib/l10n/*.arb`) — never a hardcoded string literal in `Text(...)`/`SnackBar`/`AlertDialog`.

This extends to caught errors: `AppException.message` (`lib/shared/model/app_exception.dart`) and any exception's `toString()` are English-only, meant for logs/diagnostics — never interpolate them into UI text (`context.loc.errorX(e.toString())`, `Text('$error')`, `Text('${loc.error}: ${snapshot.error}')`). Use `AppExceptionLocalization.describeError(error)` (`lib/shared/extensions/app_exception_localization.dart`) instead: it maps the exception's *type* (`NetworkException`, `ServerException`, anything else) to one of a small set of localized, parameter-free strings (`errorNetwork`, `errorServer`, `errorGeneric`), and can be composed into an existing parameterized message, e.g. `context.loc.errorSaveImage(context.loc.describeError(e))`.

`test/architecture/l10n_convention_test.dart` scans `lib/` for the common violations of this (hardcoded `Text()` literals, `.toString()` fed into a `context.loc.*(...)` call, a raw error interpolated into `Text(...)`) and fails the build if one is reintroduced.

### Testing

- **Unit tests** in `test/`, mirroring the `lib/` slice structure 1:1 (`test/catalog/`, `test/enrichment/`, `test/learning/`, `test/shared/`, `test/diagnostics/`, `test/app/`, `test/external/`) — a file under `lib/learning/decks/foo.dart` has its test at `test/learning/decks/foo_test.dart`. Shared mockito-generated mocks live at top-level `test/mocks.dart` (source) / `test/mocks.mocks.dart` (generated), imported by relative path since `test/` isn't part of the `discere` package.
- **Architecture tests** in `test/architecture/` – `module_dependency_test.dart` enforces the slice dependency matrix above; also checks logging/SafeArea/l10n conventions. Run these whenever you add a new cross-slice import.
- **Integration tests** in `integration_test/` – test files covering full user flows end-to-end
- **IMPORTANT:** When creating a new integration test file, always add it to `integration_test/all_tests.dart` (import + `main()` call). This is the single entry point used by CI to run all integration tests in one build.
- **Reference-DB test fixture**: `test/fixtures/discere_reference_test.db` is a small (~1MB), curated subset of the real reference DB (generated by `etl/scripts/build_test_fixture.sh` from a species list in `etl/scripts/test_fixture_species.txt`), checked into git. Repository tests (`test/catalog/repository/species_repository_*_test.dart`) read it directly via `dart:io` since they run on the host; integration tests read it via `rootBundle` (it's a declared `pubspec.yaml` asset, since `integration_test/test_utils.dart` runs on-device) and seed it into place before `app.main()` so tests never need real network access. If a test starts relying on a species not in the fixture, add it to `test_fixture_species.txt` and rerun the build script.
  - This fixture is a deliberate, accepted exception to "the reference DB isn't bundled" above: Flutter's asset system has no test-only scoping (unlike e.g. Gradle's `testImplementation`) — anything under `pubspec.yaml`'s `flutter: assets:` ships in every build, including real releases, because `integration_test/test_utils.dart` needs `rootBundle` access to get it onto the device at all. At ~1.4MB this is negligible next to the 400MB it replaces, so it's kept simple rather than reconstructing the fixture from raw SQL at test time (which would avoid bundling it, at the cost of duplicating schema in test code).
- CI runs on macOS via `.github/workflows/flutter_ci.yml` (analyze → test → build APK + iOS)
- Test coverage is uneven across the codebase; some previously-untested repositories/services now have coverage (`catalog/repository/`, `enrichment/pipeline/service/base_worker.dart`/`inat_worker.dart`, `learning/flashcard/deck_page.dart`'s presenter logic), but plenty of files still don't. Check for existing tests before assuming a change is covered, and prefer adding tests when touching complex logic rather than assuming it.

### ETL Pipeline

The `etl/` directory is a separate tool (bash + duckdb + sqlite) for regenerating `discere_reference.db`. It has its own `README.md` (in German) and `FLUTTER_INTEGRATION.md`. It is not part of the Flutter build.

Publishing a new reference-DB version to end users (i.e. making `ReferenceDatabaseProvisioner` actually download it) is a separate, manual, maintainer-only step: `etl/publish_release.sh` (needs the `gh` CLI, authenticated via `gh auth login`, with push access to `github.com/discere-app/discere-data`). See [GitHub issue #54](https://github.com/discere-app/discere/issues/54) for the hosting/versioning design.
