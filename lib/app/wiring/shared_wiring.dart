import 'package:discere/shared/persistence/user_data_writes.dart';
import 'package:discere/shared/service/diagnostics_sink.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/service/navigation_tab_service.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/shared/util/logging_http_client.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds the cross-cutting `shared` services every other slice is wired
/// with. Takes the already-loaded [sharedPreferences] and the diagnostics
/// sink, so this stays pure construction — the awaits that produce them
/// belong to the composition root's startup sequence.
///
/// [httpClient] replaces the *transport* the shared [LoggingHttpClient]
/// wraps, not the wrapper itself: diagnostics recording and the host
/// cooldown stay in the path, so a caller that substitutes this exercises
/// the stack the app ships and only the network is stood in for. See
/// `BootstrapApp.httpClient` for what that costs a test.
({
  ConnectivityNetworkAvailability networkAvailability,
  HostCooldownTracker hostCooldownTracker,
  LoggingHttpClient sharedHttpClient,
  ImageService imageService,
  LanguageService languageService,
  NavigationTabService navigationTabService,
  UserPreferencesService userPreferencesService,
  UserDataWrites userDataWrites,
  List<SingleChildWidget> providers,
})
buildSharedServices({
  required SharedPreferences sharedPreferences,
  required DiagnosticsSink diagnostics,
  http.Client? httpClient,
}) {
  // Single shared instance: HostCooldownTracker tracks per-host cooldown
  // state, so every consumer needs the same one rather than its own.
  final hostCooldownTracker = HostCooldownTracker();
  final sharedHttpClient = LoggingHttpClient(
    httpClient ?? http.Client(),
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
  // One per bootstrap run: the restart waits for exactly the writes this
  // run's services started.
  final userDataWrites = UserDataWrites();

  return (
    networkAvailability: ConnectivityNetworkAvailability(),
    hostCooldownTracker: hostCooldownTracker,
    sharedHttpClient: sharedHttpClient,
    imageService: imageService,
    languageService: languageService,
    navigationTabService: navigationTabService,
    userPreferencesService: userPreferencesService,
    userDataWrites: userDataWrites,
    providers: [
      ChangeNotifierProvider<NavigationTabService>.value(
        value: navigationTabService,
      ),
      Provider<ImageService>.value(value: imageService),
      ChangeNotifierProvider<LanguageService>.value(value: languageService),
      ChangeNotifierProvider<UserPreferencesService>.value(
        value: userPreferencesService,
      ),
      Provider<UserDataWrites>.value(value: userDataWrites),
    ],
  );
}
