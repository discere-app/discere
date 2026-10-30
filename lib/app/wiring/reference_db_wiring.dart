import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_db_downloader.dart';
import 'package:discere/shared/persistence/reference_db_update_service.dart';
import 'package:discere/shared/service/foreground_service_keeper.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:discere/shared/util/user_agent_http_client.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// The reference-database objects, which the bootstrap holds across runs.
typedef ReferenceDbServices = ({
  ReferenceDatabaseProvisioner provisioner,
  ReferenceDbUpdateService updates,
});

/// Builds the provisioner of the reference database and the update service
/// over it. Runs before every other wiring, since nothing else can be built
/// until the reference database is in place.
///
/// [downloader] stands in for the real one; see
/// `BootstrapApp.referenceDbDownloader`. [httpClient] instead replaces only
/// the transport under the real downloader's client, the way
/// `buildSharedServices` takes it.
ReferenceDbServices buildReferenceDbServices({
  required PackageInfo packageInfo,
  required ForegroundServiceKeeper foregroundServiceKeeper,
  ReferenceDbDownloader? downloader,
  http.Client? httpClient,
}) {
  final provisioner = ReferenceDatabaseProvisioner(
    downloader:
        downloader ??
        ReferenceDbDownloader(
          // Not the LoggingHttpClient the shared wiring builds: this runs
          // before diagnostics and the host cooldown exist.
          client: UserAgentHttpClient(
            httpClient ?? http.Client(),
            AppConstants.userAgentFor(packageInfo.version),
          ),
          foregroundServiceKeeper: foregroundServiceKeeper,
        ),
    closeOpenDatabases: DatabaseHelper.close,
  );
  return (
    provisioner: provisioner,
    updates: ReferenceDbUpdateService(
      provisioner: provisioner,
      // Own instance, separate from the one the shared wiring builds — this
      // one only answers one-shot isOnWifi() checks, from before that wiring
      // exists, and is never initialize()d (no stream consumer).
      networkAvailability: ConnectivityNetworkAvailability(),
    ),
  );
}
