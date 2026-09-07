import 'package:discere/app/diagnostics/diagnostics_page_data.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_section_widgets.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:flutter/material.dart';

/// At-a-glance dashboard, first thing on the page: the four numbers that
/// answer "is anything wrong right now" without expanding a section.
class DiagnosticsSummaryCard extends StatelessWidget {
  final DiagnosticsPageData data;
  final HostCooldownSnapshot? cooldown;

  const DiagnosticsSummaryCard({
    required this.data,
    required this.cooldown,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.loc.diagnosticsSummaryTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DiagnosticsMetricChip(
                  label: context.loc.diagnosticsMetricNetworkFailures,
                  value: '${data.report.totalNetworkFailureCount}',
                ),
                DiagnosticsMetricChip(
                  label: context.loc.diagnosticsMetricOutstandingEnrichmentWork,
                  value: '${data.healthSnapshot.outstandingWorkCount}',
                ),
                DiagnosticsMetricChip(
                  label: context.loc.diagnosticsMetricHostCooldownActive,
                  value: cooldown == null
                      ? context.loc.commonNo
                      : context.loc.commonYes,
                ),
                DiagnosticsMetricChip(
                  label: context.loc.diagnosticsMetricTotalSpecies,
                  value: '${data.totalSpeciesCount}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
