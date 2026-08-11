class AppConstants {
  static const String notificationPayloadDailyReview = 'daily_review';

  static const String developerName = 'Fabian Eberle';
  static const String feedbackEmail = 'dev.feberle@gmail.com';
  static const String repositoryUrl = 'https://github.com/discere-app/discere';
  static const String dataRepositoryUrl =
      'https://github.com/discere-app/discere-data';
  static const String bundleId = 'ch.feberle.discere';
  static const String userAgent = 'DiscereApp/1.1 ($bundleId; $repositoryUrl)';

  /// SharedPreferences key gating the Diagnostics settings tile. Set by
  /// repeatedly tapping the app version number on the About page, read by
  /// the Settings page when it returns from About.
  static const String developerDiagnosticsUnlockedPrefKey =
      'developer.diagnostics.unlocked';
}
