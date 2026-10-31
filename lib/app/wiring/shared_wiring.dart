import 'package:discere/shared/persistence/user_data_writes.dart';
import 'package:discere/shared/service/diagnostics_sink.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/service/navigation_tab_service.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:discere/shared/util/logging_http_client.dart';
import 'package:discere/shared/util/user_agent_http_client.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The `shared` services, as the composition root hands them on.
typedef SharedServices = ({
  ConnectivityNetworkAvailability networkAvailability,
  HostCooldownTracker hostCooldownTracker,
  LoggingHttpClient sharedHttpClient,
  ImageService imageService,
  LanguageService languageService,
  NavigationTabService navigationTabService,
  UserPreferencesService userPreferencesService,
  UserDataWrites userDataWrites,
  List<SingleChildWidget> providers,
});

/// Builds the cross-cutting `shared` services every other slice is wired
/// with. Takes the already-loaded [sharedPreferences], the diagnostics sink
/// and the [packageInfo] `main()` read, so this stays pure construction —
/// the awaits that produce them belong to the composition root's startup
/// sequence.
///
/// [httpClient] replaces the *transport* the shared [LoggingHttpClient]
/// wraps, not the wrapper itself: the app's User-Agent, diagnostics
/// recording and the host cooldown stay in the path, so a caller that
/// substitutes this exercises the stack the app ships and only the network
/// is stood in for. See `BootstrapApp.httpClient` for what that costs a
/// test.
SharedServices buildSharedServices({
  required SharedPreferences sharedPreferences,
  required DiagnosticsSink diagnostics,
  required PackageInfo packageInfo,
  http.Client? httpClient,
}) {
  // Single shared instance: HostCooldownTracker tracks per-host cooldown
  // state, so every consumer needs the same one rather than its own.
  final hostCooldownTracker = HostCooldownTracker();
  final sharedHttpClient = LoggingHttpClient(
    UserAgentHttpClient(
      httpClient ?? http.Client(),
      AppConstants.userAgentFor(packageInfo.version),
    ),
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
      Provider<PackageInfo>.value(value: packageInfo),
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
