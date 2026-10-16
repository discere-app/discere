import 'package:discere/app/diagnostics/diagnostics_page_data.dart';
import 'package:discere/catalog/model/source.dart';
import 'package:discere/diagnostics/model/local_diagnostics_report.dart';
import 'package:discere/enrichment/queue/service/enrichment_health_snapshot_service.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_db_update_state.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration_run.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Page data with nothing to report but the reference-DB facts a test sets.
DiagnosticsPageData diagnosticsPageData({
  DateTime? referenceDbFileModifiedAt,
  List<Source> referenceDbSources = const [],
  ReferenceDbUpdateState referenceDbUpdateState = const ReferenceDbUpToDate(),
  int? referenceIdsAppliedVersion,
  ReferenceIdMigrationRun? lastReferenceIdMigrationRun,
}) => DiagnosticsPageData(
  report: const LocalDiagnosticsReport(
    totalNetworkFailureCount: 0,
    hostFailures: [],
    recentFailures: [],
  ),
  healthSnapshot: const EnrichmentHealthSnapshot(
    workStateCounts: [],
    coverJobs: [],
  ),
  referenceDbStatus: ReferenceDbStatus(
    installedVersion: 7,
    installedSchemaVersion: 2,
    supportedSchemaVersions: {1, 2},
    fileExists: true,
    fileSizeBytes: 86 * 1024 * 1024,
    fileModifiedAt: referenceDbFileModifiedAt,
  ),
  referenceDbSources: referenceDbSources,
  referenceDbUpdateState: referenceDbUpdateState,
  referenceIdsAppliedVersion: referenceIdsAppliedVersion,
  lastReferenceIdMigrationRun: lastReferenceIdMigrationRun,
  foregroundServiceRunning: false,
  packageInfo: PackageInfo(
    appName: 'Discere',
    packageName: 'app.discere',
    version: '1.0.0',
    buildNumber: '1',
  ),
  persistErrorLogs: false,
  totalSpeciesCount: 0,
);

/// A source as the reference database lists it.
Source referenceDbSource(
  String id,
  String name, {
  String? version,
  int displayOrder = 10,
}) => Source(
  id: id,
  name: name,
  category: 'Database',
  citation: name,
  url: 'https://example.org/$id',
  licenseKey: 'CC BY-NC',
  version: version,
  displayOrder: displayOrder,
);
