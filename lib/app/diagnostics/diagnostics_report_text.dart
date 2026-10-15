/// Renders [DiagnosticsPageData] as the plain-text report the share and copy
/// actions hand out.
///
/// Deliberately not a widget: it is the same data the page shows, flattened
/// for a bug report, and keeping it beside the page rather than inside it
/// means neither the sections nor the report can quietly drift from the
/// grouping in `diagnostics_formatting.dart` they both use.
library;

import 'dart:io';

import 'package:discere/app/diagnostics/diagnostics_formatting.dart';
import 'package:discere/app/diagnostics/diagnostics_page_data.dart';
import 'package:discere/shared/persistence/reference_db_update_state.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration_run.dart';

String buildDiagnosticsReportText(DiagnosticsPageData data) {
  final buffer = StringBuffer()
    ..writeln('Discere diagnostics report')
    ..writeln(
      'app: ${data.packageInfo.appName} ${data.packageInfo.version} '
      '(${data.packageInfo.buildNumber})',
    )
    ..writeln(
      'platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    )
    ..writeln()
    ..writeln(
      'reference db: installed=${data.referenceDbStatus.installedVersion} '
      'schema=${data.referenceDbStatus.installedSchemaVersion}/'
      '${data.referenceDbStatus.supportedSchemaVersions.join(',')} '
      'exists=${data.referenceDbStatus.fileExists}',
    )
    ..writeln('reference db sources: ${_referenceDbSourcesText(data)}')
    ..writeln(
      'reference db update: ${_updateStateText(data.referenceDbUpdateState)}',
    )
    ..writeln('reference ids applied: ${data.referenceIdsAppliedVersion}');
  _writeLastReferenceIdMigrationRun(buffer, data.lastReferenceIdMigrationRun);
  buffer
    ..writeln('foreground service running: ${data.foregroundServiceRunning}')
    ..writeln()
    ..writeln('enrichment queue:');
  final grouped = groupWorkStateCounts(data.healthSnapshot);
  for (final entry in grouped.entries) {
    final states = entry.value
        .map(
          (state) => state.nextAttemptAt == null
              ? '${state.state}=${state.count}'
              : '${state.state}=${state.count} '
                    '(next ${state.nextAttemptAt!.toIso8601String()})',
        )
        .join(', ');
    buffer.writeln('- ${entry.key}: $states');
  }
  buffer
    ..writeln()
    ..writeln('cover jobs:');
  for (final job in data.healthSnapshot.coverJobs) {
    buffer.writeln(
      '- ${job.deckId}: ${job.status.name} '
      'cover=${job.coverState.wireName} retries=${job.retryCount}',
    );
  }
  buffer
    ..writeln()
    ..writeln('network failures: ${data.report.totalNetworkFailureCount}');
  for (final host in data.report.hostFailures.take(10)) {
    buffer.writeln(
      '- ${host.host}: ${host.failureCount} '
      '(${host.retryableFailureCount} retryable)',
    );
  }
  buffer
    ..writeln()
    ..writeln('recent failures:');
  for (final failure in data.report.recentFailures.take(20)) {
    buffer.writeln(
      '- ${failure.createdAt.toIso8601String()} '
      '${failure.method} ${requestUrlOf(failure)} '
      '${failure.statusCode ?? failure.exceptionType ?? '-'} '
      '${failure.message ?? ''}',
    );
  }
  return buffer.toString();
}

String _updateStateText(ReferenceDbUpdateState state) => switch (state) {
  ReferenceDbUpdateNotChecked() => 'not-checked',
  ReferenceDbUpdateChecking() => 'checking',
  ReferenceDbUpdateCheckFailed() => 'check-failed',
  ReferenceDbUpToDate() => 'up-to-date',
  ReferenceDbUpdateAvailable(:final update, :final declined) =>
    'available v${update.version}${declined ? ' declined' : ''}',
  ReferenceDbUpdateDownloading(:final update, :final progress) =>
    'downloading v${update.version} '
        '${((progress ?? 0) * 100).floor()}%',
  ReferenceDbUpdateDownloadFailed(:final update) =>
    'download-failed v${update.version}',
  ReferenceDbUpdateStaged(:final version, :final noticeDismissed) =>
    'staged v$version${noticeDismissed ? ' notice-dismissed' : ''}',
};

String _referenceDbSourcesText(DiagnosticsPageData data) =>
    data.referenceDbSources.isEmpty
    ? 'none'
    : data.referenceDbSources
          .map((source) => '${source.id}=${source.version}')
          .join(', ');

void _writeLastReferenceIdMigrationRun(
  StringBuffer buffer,
  ReferenceIdMigrationRun? run,
) {
  final prefix = 'reference id last run:';
  switch (run) {
    case null:
      buffer.writeln('$prefix none');
    case ReferenceIdMigrationFailed():
      buffer.writeln(
        '$prefix failed v${run.referenceDbVersion} '
        'at ${run.ranAt.toIso8601String()}',
      );
    case ReferenceIdMigrationSucceeded():
      buffer.writeln(
        '$prefix succeeded v${run.referenceDbVersion} '
        'at ${run.ranAt.toIso8601String()} '
        'referenced=${run.referencedIdCount} aliased=${run.aliasCount} '
        'rewritten=${run.totalRewritten} dropped=${run.totalDropped}',
      );
      for (final MapEntry(key: target, value: count) in run.targets.entries) {
        buffer.writeln(
          '- $target: ${count.rewritten} rewritten, ${count.dropped} dropped',
        );
      }
  }
}
