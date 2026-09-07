import 'package:discere/app/diagnostics/diagnostics_formatting.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_section_widgets.dart';
import 'package:discere/diagnostics/repository/local_diagnostics_repository.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Failures by host and the raw recent-failures list as one section — both
/// are views over the same network-failure data the summary card's
/// "HTTP failures" metric counts, so they sit directly below it.
class DiagnosticsFailuresSection extends StatelessWidget {
  final LocalDiagnosticsReport report;

  const DiagnosticsFailuresSection({required this.report, super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          DiagnosticsSectionHeader(
            title: context.loc.diagnosticsFailuresTitle,
          ),
          ExpansionTile(
            initiallyExpanded: report.hostFailures.isNotEmpty,
            title: Text(context.loc.diagnosticsFailuresByHostTitle),
            children: report.hostFailures.isEmpty
                ? [const DiagnosticsEmptyRow()]
                : report.hostFailures
                      .take(8)
                      .map(
                        (summary) => ListTile(
                          dense: true,
                          title: Text(summary.host),
                          subtitle: Text(
                            '${summary.retryableFailureCount}/${summary.failureCount}',
                          ),
                          trailing: Text(
                            formatDiagnosticsDateTime(
                              context,
                              summary.lastFailureAt,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
          ),
          const Divider(height: 1),
          ExpansionTile(
            title: Text(context.loc.diagnosticsRecentFailuresTitle),
            children: report.recentFailures.isEmpty
                ? [const DiagnosticsEmptyRow()]
                : report.recentFailures
                      .take(12)
                      .map(
                        (failure) => ListTile(
                          dense: true,
                          title: Text(
                            '${failure.host} • ${failure.statusCode ?? failure.exceptionType ?? '-'}',
                          ),
                          subtitle: Text(
                            [
                              '${failure.method} ${requestUrlOf(failure)}',
                              if (failure.message != null) failure.message!,
                            ].join('\n'),
                          ),
                          trailing: Text(
                            formatDiagnosticsDateTime(
                              context,
                              failure.createdAt,
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      )
                      .toList(growable: false),
          ),
        ],
      ),
    );
  }
}
