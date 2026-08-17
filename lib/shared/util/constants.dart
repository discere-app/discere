import 'package:discere/shared/util/dev_data_source_override.dart';
import 'package:flutter/foundation.dart';

class AppConstants {
  static const String notificationPayloadDailyReview = 'daily_review';

  static const String developerName = 'Fabian Eberle';
  static const String feedbackEmail = 'dev.feberle@gmail.com';
  static const String repositoryUrl = 'https://github.com/discere-app/discere';
  static const String dataRepositoryUrl =
      'https://github.com/discere-app/discere-data';

  static const String _prodDiscereDataContentBaseUrl =
      'https://raw.githubusercontent.com/discere-app/discere-data/main';
  static const String _prodDeckCatalogIndexUrl =
      '$_prodDiscereDataContentBaseUrl/data/decks/index.json';
  static const String _prodReferenceDbManifestUrl =
      '$_prodDiscereDataContentBaseUrl/data/reference-db/manifest.json';

  /// The online deck catalog, fetched by `RemoteDeckService`. Always
  /// production in a release/profile build; in a debug build, uses
  /// [devDeckCatalogIndexUrlOverride] instead if that's set — see its doc
  /// for how to point local runs at a test branch without any extra launch
  /// parameter.
  ///
  /// [dataRepositoryUrl] above is a separate, human-facing link (About page
  /// attribution) and deliberately does NOT use this override — it should
  /// always point at the real repo for users to open in a browser.
  static const String deckCatalogIndexUrl = kDebugMode
      ? (devDeckCatalogIndexUrlOverride ?? _prodDeckCatalogIndexUrl)
      : _prodDeckCatalogIndexUrl;

  /// The reference species DB manifest, fetched by
  /// `ReferenceDatabaseProvisioner`. Same override mechanism as
  /// [deckCatalogIndexUrl], via [devReferenceDbManifestUrlOverride] —
  /// deliberately a separate constant rather than sharing one base-URL
  /// override, since the two aren't equally safe to redirect: the reference
  /// DB blocks app startup if it can't be fetched/installed, so pointing it
  /// at a broken or missing manifest breaks every debug launch, not just
  /// whatever you're actually testing.
  static const String referenceDbManifestUrl = kDebugMode
      ? (devReferenceDbManifestUrlOverride ?? _prodReferenceDbManifestUrl)
      : _prodReferenceDbManifestUrl;

  static const String bundleId = 'ch.feberle.discere';
  static const String userAgent = 'DiscereApp/1.1 ($bundleId; $repositoryUrl)';

  /// SharedPreferences key gating the Diagnostics settings tile. Set by
  /// repeatedly tapping the app version number on the About page, read by
  /// the Settings page when it returns from About.
  static const String developerDiagnosticsUnlockedPrefKey =
      'developer.diagnostics.unlocked';
}
