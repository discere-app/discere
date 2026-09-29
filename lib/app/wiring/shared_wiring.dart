import 'package:discere/shared/service/diagnostics_sink.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/service/navigation_tab_service.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/shared/util/logging_http_client.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Builds the cross-cutting `shared` services every other slice is wired
/// with. Takes the already-loaded [sharedPreferences] and the diagnostics
/// sink, so this stays pure construction — the awaits that produce them
/// belong to the composition root's startup sequence.
({
  NetworkAvailability networkAvailability,
  HostCooldownTracker hostCooldownTracker,
  LoggingHttpClient sharedHttpClient,
  ImageService imageService,
  LanguageService languageService,
  NavigationTabService navigationTabService,
  UserPreferencesService userPreferencesService,
})
buildSharedServices({
  required SharedPreferences sharedPreferences,
  required DiagnosticsSink diagnostics,
}) {
  // Single shared instance: HostCooldownTracker tracks per-host cooldown
  // state, so every consumer needs the same one rather than its own.
  final hostCooldownTracker = HostCooldownTracker();
  final sharedHttpClient = LoggingHttpClient(
    http.Client(),
    diagnostics: diagnostics,
    hostCooldownTracker: hostCooldownTracker,
  );
  final imageService = ImageService(
    client: sharedHttpClient,
    hostCooldownTracker: hostCooldownTracker,
  );
  final languageService = LanguageService(sharedPreferences);
  final navigationTabService = NavigationTabService();
  final userPreferencesService = UserPreferencesService(sharedPreferences);

  return (
    networkAvailability: ConnectivityNetworkAvailability(),
    hostCooldownTracker: hostCooldownTracker,
    sharedHttpClient: sharedHttpClient,
    imageService: imageService,
    languageService: languageService,
    navigationTabService: navigationTabService,
    userPreferencesService: userPreferencesService,
  );
}
