import 'package:discere/app/diagnostics/diagnostics_formatting.dart';
import 'package:discere/app/diagnostics/diagnostics_page_data.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_section_widgets.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/enrichment_work_state_count.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:flutter/material.dart';

/// Everything enrichment-related — queue, cover jobs, iNaturalist cooldown,
/// foreground service, and the two enrichment actions — as one section rather
/// than five separate cards a reader has to mentally group themselves.
class DiagnosticsEnrichmentSection extends StatelessWidget {
  final DiagnosticsPageData data;
  final HostCooldownSnapshot? cooldown;
  final VoidCallback onResetStuckJobs;
  final VoidCallback onCloseAllEnrichment;

  const DiagnosticsEnrichmentSection({
    required this.data,
    required this.cooldown,
    required this.onResetStuckJobs,
    required this.onCloseAllEnrichment,
    super.key,
  });

  /// `state: count`, plus how long until the next retry when the group is
  /// waiting on one — the only state where `nextAttemptAt` is set.
  String _stateLine(BuildContext context, EnrichmentWorkStateCount state) {
    final base = '${state.state}: ${state.count}';
    final nextAttemptAt = state.nextAttemptAt;
    if (state.state != EnrichmentWorkState.retryScheduled ||
        nextAttemptAt == null) {
      return base;
    }
    final remaining = nextAttemptAt.difference(DateTime.now());
    final eta = remaining.isNegative
        ? context.loc.diagnosticsNextRetryDue
        : context.loc.diagnosticsNextRetryIn(
            formatDiagnosticsDuration(remaining),
          );
    return '$base — $eta';
  }

  @override
  Widget build(BuildContext context) {
    final grouped = groupWorkStateCounts(data.healthSnapshot);
    final coverJobs = data.healthSnapshot.coverJobs;
    final activeCooldown = cooldown;
    return Card(
      child: Column(
        children: [
          DiagnosticsSectionHeader(
            title: context.loc.diagnosticsEnrichmentSectionTitle,
          ),
          ExpansionTile(
            initiallyExpanded: grouped.isNotEmpty,
            title: Text(context.loc.diagnosticsEnrichmentQueueTitle),
            children: grouped.isEmpty
                ? [const DiagnosticsEmptyRow()]
                : grouped.entries
                      .map(
                        (entry) => ListTile(
                          dense: true,
                          title: Text(entry.key),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: entry.value
                                .map(
                                  (state) => Text(_stateLine(context, state)),
                                )
                                .toList(growable: false),
                          ),
                        ),
                      )
                      .toList(growable: false),
          ),
          const Divider(height: 1),
          ExpansionTile(
            title: Text(context.loc.diagnosticsCoverJobsTitle),
            children: coverJobs.isEmpty
                ? [const DiagnosticsEmptyRow()]
                : coverJobs
                      .map(
                        (job) => ListTile(
                          dense: true,
                          title: Text('${job.deckId} • ${job.status.name}'),
                          subtitle: Text(
                            [
                              'cover ${job.coverState.wireName}',
                              'retries ${job.retryCount}',
                              if (job.leaseOwner != null)
                                'lease ${job.leaseOwner}',
                              if (job.lastError != null) job.lastError!,
                            ].join(' • '),
                          ),
                        ),
                      )
                      .toList(growable: false),
          ),
          const Divider(height: 1),
          ListTile(
            title: Text(context.loc.diagnosticsHostCooldownTitle),
            subtitle: Text(
              activeCooldown == null
                  ? context.loc.diagnosticsHostCooldownNone
                  : context.loc.diagnosticsHostCooldownActive(
                      activeCooldown.host,
                      formatDiagnosticsDuration(activeCooldown.remaining()),
                    ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: Text(context.loc.diagnosticsForegroundServiceTitle),
            subtitle: Text(
              data.foregroundServiceRunning
                  ? context.loc.diagnosticsForegroundServiceRunning
                  : context.loc.diagnosticsForegroundServiceNotRunning,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: Text(context.loc.diagnosticsResetStuckJobs),
            onTap: onResetStuckJobs,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.playlist_remove),
            title: Text(context.loc.diagnosticsCloseAllEnrichment),
            onTap: onCloseAllEnrichment,
          ),
        ],
      ),
    );
  }
}
