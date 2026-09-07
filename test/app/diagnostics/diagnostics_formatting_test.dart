/// Covers the pure parts of the diagnostics page, which only became reachable
/// once they moved out of the page's private methods.
///
/// The report text in particular is what a user pastes into a bug report, and
/// it shares its grouping with the on-screen section — so a change that
/// reorders one silently reorders the other.
library;

import 'package:discere/app/diagnostics/diagnostics_formatting.dart';
import 'package:discere/diagnostics/model/local_diagnostics_report.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/enrichment_work_state_count.dart';
import 'package:discere/enrichment/queue/service/enrichment_health_snapshot_service.dart';
import 'package:flutter_test/flutter_test.dart';

EnrichmentWorkStateCount _count(
  String label,
  EnrichmentWorkState state, {
  int count = 1,
  DateTime? nextAttemptAt,
}) => EnrichmentWorkStateCount(
  label: label,
  state: state,
  count: count,
  nextAttemptAt: nextAttemptAt,
);

LocalDiagnosticsNetworkFailureRecord _failure({
  Map<String, Object?> details = const {},
  String urlPath = '/v2/taxa',
}) => LocalDiagnosticsNetworkFailureRecord(
  createdAt: DateTime(2026, 1, 1),
  host: 'api.inaturalist.org',
  method: 'GET',
  urlPath: urlPath,
  statusCode: 429,
  exceptionType: null,
  message: null,
  durationMs: null,
  retryable: true,
  details: details,
);

void main() {
  group('groupWorkStateCounts', () {
    test('groups by label, labels sorted alphabetically', () {
      final grouped = groupWorkStateCounts(
        EnrichmentHealthSnapshot(
          coverJobs: const [],
          workStateCounts: [
            _count('inatPrimary', EnrichmentWorkState.done),
            _count('base', EnrichmentWorkState.done),
            _count('base', EnrichmentWorkState.pending),
          ],
        ),
      );

      expect(grouped.keys, ['base', 'inatPrimary']);
      expect(grouped['base'], hasLength(2));
    });

    test('orders states by lifecycle, not alphabetically', () {
      // Alphabetically this would be done, pending, retryScheduled, running.
      final grouped = groupWorkStateCounts(
        EnrichmentHealthSnapshot(
          coverJobs: const [],
          workStateCounts: [
            _count('base', EnrichmentWorkState.done),
            _count('base', EnrichmentWorkState.retryScheduled),
            _count('base', EnrichmentWorkState.pending),
            _count('base', EnrichmentWorkState.running),
          ],
        ),
      );

      expect(grouped['base']!.map((c) => c.state), [
        EnrichmentWorkState.pending,
        EnrichmentWorkState.running,
        EnrichmentWorkState.retryScheduled,
        EnrichmentWorkState.done,
      ]);
    });

    test('an empty snapshot groups to nothing', () {
      final grouped = groupWorkStateCounts(
        const EnrichmentHealthSnapshot(coverJobs: [], workStateCounts: []),
      );
      expect(grouped, isEmpty);
    });
  });

  group('requestUrlOf', () {
    test('prefers the full URL captured in details', () {
      expect(
        requestUrlOf(
          _failure(details: {'requestUrl': 'https://host/v2/taxa?q=fish'}),
        ),
        'https://host/v2/taxa?q=fish',
      );
    });

    test('falls back to the bare path when details carries nothing', () {
      expect(requestUrlOf(_failure(urlPath: '/v2/taxa')), '/v2/taxa');
    });
  });

  group('formatDiagnosticsDuration', () {
    test('drops the minute part below a minute', () {
      expect(formatDiagnosticsDuration(const Duration(seconds: 42)), '42s');
    });

    test('shows minutes and remaining seconds above a minute', () {
      expect(
        formatDiagnosticsDuration(const Duration(minutes: 2, seconds: 5)),
        '2m 5s',
      );
    });
  });
}
