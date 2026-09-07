import 'package:discere/app/diagnostics/diagnostics_actions.dart';
import 'package:discere/app/diagnostics/diagnostics_page_data.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_app_info_section.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_enrichment_section.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_failures_section.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_general_actions_card.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_log_card.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_section_widgets.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_summary_card.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:flutter/material.dart';

/// The page's sections, ordered by how actionable each one is: the
/// at-a-glance dashboard first, static facts about the install last.
class DiagnosticsSectionList extends StatelessWidget {
  final DiagnosticsPageData data;
  final HostCooldownSnapshot? cooldown;
  final DateTime? lastRefreshedAt;
  final bool isCheckingDeckUpdates;
  final DiagnosticsActions actions;

  const DiagnosticsSectionList({
    required this.data,
    required this.cooldown,
    required this.lastRefreshedAt,
    required this.isCheckingDeckUpdates,
    required this.actions,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      DiagnosticsLastRefreshedRow(lastRefreshedAt: lastRefreshedAt),
      DiagnosticsSummaryCard(data: data, cooldown: cooldown),
      // Failures by host and the raw list are two views over the same data
      // the summary's HTTP-failure metric counts, so they follow it.
      DiagnosticsFailuresSection(report: data.report),
      DiagnosticsLogCard(
        persistErrorLogs: data.persistErrorLogs,
        onPersistChanged: actions.setPersistLogs,
        onOpenLog: actions.openLogViewer,
        onClearLog: actions.clearLog,
      ),
      DiagnosticsEnrichmentSection(
        data: data,
        cooldown: cooldown,
        onResetStuckJobs: actions.resetStuckJobs,
        onCloseAllEnrichment: actions.closeAllEnrichment,
      ),
      DiagnosticsGeneralActionsCard(
        isCheckingDeckUpdates: isCheckingDeckUpdates,
        onCheckDeckUpdates: actions.checkDeckUpdates,
        onResetAllSettings: actions.resetAllSettings,
      ),
      DiagnosticsAppInfoSection(data: data),
    ];
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, index) => sections[index],
    );
  }
}
