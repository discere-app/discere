/// Formatting and grouping shared by the diagnostics sections and the
/// shareable report text, so the on-screen numbers and the copied ones cannot
/// disagree.
library;

import 'package:discere/diagnostics/model/local_diagnostics_report.dart';
import 'package:discere/enrichment/pipeline/model/enrichment_work_state_count.dart';
import 'package:discere/enrichment/queue/service/enrichment_health_snapshot_service.dart';
import 'package:flutter/material.dart';

/// Work-state counts grouped by label, each group in lifecycle order
/// (`pending` → `running` → … → `permanentFailure`) rather than
/// alphabetically: the point of the list is to see where work is piling up,
/// and that reads down the enum's own declaration order.
Map<String, List<EnrichmentWorkStateCount>> groupWorkStateCounts(
  EnrichmentHealthSnapshot snapshot,
) {
  final grouped = <String, List<EnrichmentWorkStateCount>>{};
  for (final entry in snapshot.workStateCounts) {
    grouped.putIfAbsent(entry.label, () => []).add(entry);
  }
  for (final states in grouped.values) {
    states.sort((left, right) => left.state.index.compareTo(right.state.index));
  }
  final sortedKeys = grouped.keys.toList()..sort();
  return {for (final key in sortedKeys) key: grouped[key]!};
}

/// The full request URL including its query string, which `LocalDiagnostics`
/// captures in [LocalDiagnosticsNetworkFailureRecord.details]. Falls back to
/// [LocalDiagnosticsNetworkFailureRecord.urlPath], all that survives if
/// `details` is empty (e.g. legacy rows).
String requestUrlOf(LocalDiagnosticsNetworkFailureRecord failure) {
  return failure.details['requestUrl'] as String? ?? failure.urlPath;
}

String formatDiagnosticsDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  if (minutes > 0) {
    return '${minutes}m ${seconds}s';
  }
  return '${duration.inSeconds}s';
}

/// Date over time on two lines — the failure lists put this in a trailing
/// column, where a single line would push the subtitle out of the row.
String formatDiagnosticsDateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final localizations = MaterialLocalizations.of(context);
  final date = localizations.formatShortDate(local);
  final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '$date\n$time';
}
