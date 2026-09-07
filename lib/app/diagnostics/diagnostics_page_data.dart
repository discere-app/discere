import 'package:discere/diagnostics/model/local_diagnostics_report.dart';
import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/diagnostics/service/log_diagnostics_persistence.dart';
import 'package:discere/enrichment/queue/service/enrichment_health_snapshot_service.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Everything the diagnostics page renders, gathered in one load so the page
/// shows a single consistent moment rather than six independently-arriving
/// snapshots.
class DiagnosticsPageData {
  final LocalDiagnosticsReport report;
  final EnrichmentHealthSnapshot healthSnapshot;
  final ReferenceDbStatus referenceDbStatus;
  final bool foregroundServiceRunning;
  final PackageInfo packageInfo;
  final bool persistErrorLogs;
  final int totalSpeciesCount;

  const DiagnosticsPageData({
    required this.report,
    required this.healthSnapshot,
    required this.referenceDbStatus,
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
    required INatEnrichmentQueueService queueService,
    required DecksService decksService,
    required LogDiagnosticsPersistence logPersistence,
  }) async {
    final results = await Future.wait([
      diagnostics.loadReport(),
      healthSnapshotService.loadSnapshot(),
      referenceDbProvisioner.currentStatus(),
      queueService.isForegroundServiceRunning,
      PackageInfo.fromPlatform(),
      decksService.getTotalDistinctSpeciesCount(),
    ]);
    return DiagnosticsPageData(
      report: results[0] as LocalDiagnosticsReport,
      healthSnapshot: results[1] as EnrichmentHealthSnapshot,
      referenceDbStatus: results[2] as ReferenceDbStatus,
      foregroundServiceRunning: results[3] as bool,
      packageInfo: results[4] as PackageInfo,
      persistErrorLogs: logPersistence.isEnabled,
      totalSpeciesCount: results[5] as int,
    );
  }
}
