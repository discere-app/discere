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
      '${data.referenceDbStatus.supportedSchemaVersion} '
      'exists=${data.referenceDbStatus.fileExists}',
    )
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
