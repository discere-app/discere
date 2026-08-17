/// Local development overrides for `AppConstants`' discere-data URLs.
///
/// Only take effect in debug builds — each `AppConstants` URL gates its own
/// override behind `kDebugMode`, so a release/profile build ignores this
/// file entirely no matter what it holds. That makes it safe to commit with
/// real branch URLs: point one at a `discere-app/discere-data` branch you
/// control to exercise catalog-update or reference-DB-update flows against
/// data you control, then set it back to `null` to fall back to production
/// for normal debug runs — no `--dart-define` or extra launch parameter
/// needed, so `flutter run` / Android Studio's Run button pick it up
/// automatically.
///
/// Kept as two independent constants rather than one shared base URL: the
/// reference DB blocks app startup if it can't be fetched, so you'd rarely
/// want to redirect it just because you're testing the deck catalog (or vice
/// versa).
library;

/// Overrides `AppConstants.deckCatalogIndexUrl`.
const String? devDeckCatalogIndexUrlOverride = null;
// Example while testing:
// const String? devDeckCatalogIndexUrlOverride =
//     'https://raw.githubusercontent.com/discere-app/discere-data/test-data/data/decks/index.json';

/// Overrides `AppConstants.referenceDbManifestUrl`.
const String? devReferenceDbManifestUrlOverride = null;
// Example while testing:
// const String? devReferenceDbManifestUrlOverride =
//     'https://raw.githubusercontent.com/discere-app/discere-data/test-data/data/reference-db/manifest.json';
