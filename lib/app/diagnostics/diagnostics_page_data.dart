import 'package:discere/catalog/model/source.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/diagnostics/model/local_diagnostics_report.dart';
import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/diagnostics/service/log_diagnostics_persistence.dart';
import 'package:discere/enrichment/queue/service/enrichment_health_snapshot_service.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/persistence/closed_database_tolerance.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_db_update_service.dart';
import 'package:discere/shared/persistence/reference_db_update_state.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration_run.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything the diagnostics page renders, gathered in one load so the page
/// shows a single consistent moment rather than six independently-arriving
/// snapshots.
class DiagnosticsPageData {
  static final _log = Logger.forType(DiagnosticsPageData);

  final LocalDiagnosticsReport report;
  final EnrichmentHealthSnapshot healthSnapshot;
  final ReferenceDbStatus referenceDbStatus;

  /// The data sources of the installed reference database that state which
  /// release of theirs it was built from, in display order. Empty when the
  /// database could not be read.
  final List<Source> referenceDbSources;

  /// Where this session stands with a newer reference database.
  final ReferenceDbUpdateState referenceDbUpdateState;

  /// The version whose aliases the user's data was last brought in line
  /// with; behind [ReferenceDbStatus.installedVersion] while that has not
  /// succeeded yet.
  final int? referenceIdsAppliedVersion;
  final ReferenceIdMigrationRun? lastReferenceIdMigrationRun;
  final bool foregroundServiceRunning;
  final PackageInfo packageInfo;
  final bool persistErrorLogs;
  final int totalSpeciesCount;

  const DiagnosticsPageData({
    required this.report,
    required this.healthSnapshot,
    required this.referenceDbStatus,
    required this.referenceDbSources,
    required this.referenceDbUpdateState,
    required this.referenceIdsAppliedVersion,
    required this.lastReferenceIdMigrationRun,
    required this.foregroundServiceRunning,
    required this.packageInfo,
    required this.persistErrorLogs,
    required this.totalSpeciesCount,
  });

  /// Gathers every source in parallel. Kept here rather than in the page
  /// because none of it touches a `BuildContext` — it is the data object
  /// knowing where it comes from, not the widget doing IO.
  static Future<DiagnosticsPageData> load({
    required LocalDiagnostics diagnostics,
    required EnrichmentHealthSnapshotService healthSnapshotService,
    required ReferenceDatabaseProvisioner referenceDbProvisioner,
    required ReferenceDbUpdateService referenceDbUpdates,
    required INatEnrichmentQueueService queueService,
    required DecksService decksService,
    required SourceService sourceService,
    required LogDiagnosticsPersistence logPersistence,
  }) async {
    final results = await Future.wait([
      diagnostics.loadReport(),
      healthSnapshotService.loadSnapshot(),
      referenceDbProvisioner.currentStatus(),
      queueService.isForegroundServiceRunning,
      PackageInfo.fromPlatform(),
      decksService.getTotalDistinctSpeciesCount(),
      SharedPreferences.getInstance(),
      loadReferenceDbSources(sourceService),
    ]);
    final preferences = results[6] as SharedPreferences;
    return DiagnosticsPageData(
      report: results[0] as LocalDiagnosticsReport,
      healthSnapshot: results[1] as EnrichmentHealthSnapshot,
      referenceDbStatus: results[2] as ReferenceDbStatus,
      referenceDbSources: results[7] as List<Source>,
      referenceDbUpdateState: referenceDbUpdates.state,
      referenceIdsAppliedVersion: preferences.getInt(
        ReferenceIdMigration.prefKeyAppliedVersion,
      ),
      lastReferenceIdMigrationRun: ReferenceIdMigrationRun.read(preferences),
      foregroundServiceRunning: results[3] as bool,
      packageInfo: results[4] as PackageInfo,
      persistErrorLogs: logPersistence.isEnabled,
      totalSpeciesCount: results[5] as int,
    );
  }

  /// The sources for [referenceDbSources]. A database that cannot be read
  /// is exactly what this page may have to show, so that costs the line,
  /// not the page.
  static Future<List<Source>> loadReferenceDbSources(
    SourceService sourceService,
  ) async {
    try {
      return await sourceService.getVersionedSources();
    } catch (error, stackTrace) {
      // Closed underneath by a restart: the page is on its way out anyway.
      if (isClosedDatabaseError(error)) return const [];
      _log.warn(
        'Reference DB sources unavailable',
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }
}
