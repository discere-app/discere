import 'dart:async';
import 'dart:io';

import 'package:discere/app/diagnostics_log_viewer_page.dart';
import 'package:discere/diagnostics/repository/local_diagnostics_repository.dart';
import 'package:discere/diagnostics/service/diagnostics_log_file.dart';
import 'package:discere/diagnostics/service/log_diagnostics_persistence.dart';
import 'package:discere/enrichment/pipeline/model/enrichment_work_state_count.dart';
import 'package:discere/enrichment/queue/service/enrichment_health_snapshot_service.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  // Below this interval since the last refresh, a queue-service change
  // notification is ignored — the pipeline can notify in rapid bursts while
  // actively processing, and re-querying the DB on every single one would
  // be wasted work for a snapshot the user is just glancing at.
  static const _autoRefreshMinInterval = Duration(seconds: 2);

  final LocalDiagnosticsRepository _repository =
      const LocalDiagnosticsRepository();
  final EnrichmentHealthSnapshotService _healthSnapshotService =
      const EnrichmentHealthSnapshotService();
  late final DiagnosticsLogFile _logFile;
  late final ReferenceDatabaseProvisioner _referenceDbProvisioner;
  late final INatEnrichmentQueueService _queueService;
  late final DeckUpdateService _deckUpdateService;
  late final DecksService _decksService;
  Future<_DiagnosticsPageData>? _future;
  bool _isRefreshing = false;
  bool _isCheckingDeckUpdates = false;
  DateTime? _lastRefreshedAt;

  @override
  void initState() {
    super.initState();
    _logFile = Provider.of<DiagnosticsLogFile>(context, listen: false);
    _referenceDbProvisioner = ReferenceDatabaseProvisioner(
      client: http.Client(),
    );
    _queueService = Provider.of<INatEnrichmentQueueService>(
      context,
      listen: false,
    );
    _queueService.addListener(_handleQueueServiceChanged);
    _deckUpdateService = Provider.of<DeckUpdateService>(context, listen: false);
    _decksService = Provider.of<DecksService>(context, listen: false);
    _future = _load();
  }

  @override
  void dispose() {
    _queueService.removeListener(_handleQueueServiceChanged);
    super.dispose();
  }

  /// Fires whenever the enrichment pipeline notifies (job claimed, work
  /// finished, state refreshed, ...) while this page is open — re-queries
  /// the snapshot so the page reflects live progress without the user
  /// having to pull-to-refresh, while [_autoRefreshMinInterval] and the
  /// [_isRefreshing] guard keep a notification burst from hammering the DB.
  void _handleQueueServiceChanged() {
    if (_isRefreshing) return;
    final lastRefreshedAt = _lastRefreshedAt;
    if (lastRefreshedAt != null &&
        DateTime.now().difference(lastRefreshedAt) < _autoRefreshMinInterval) {
      return;
    }
    unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final activeCooldown = context
        .watch<INatEnrichmentQueueService>()
        .activeCooldown;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.loc.diagnosticsTitle),
        actions: [
          IconButton(
            tooltip: context.loc.diagnosticsShareReport,
            onPressed: _shareReport,
            icon: const Icon(Icons.ios_share_outlined),
          ),
          IconButton(
            tooltip: context.loc.diagnosticsCopyReport,
            onPressed: _copyReport,
            icon: const Icon(Icons.copy_all_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<_DiagnosticsPageData>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildLastRefreshedRow(context),
                  const SizedBox(height: 12),
                  // Quick at-a-glance dashboard — first thing on the page.
                  _buildSummaryCard(context, data, activeCooldown),
                  const SizedBox(height: 12),
                  // Failures by host and the raw recent-failures list are
                  // just two views over the same data the Übersicht's
                  // "HTTP-Fehler" metric counts — grouped right below it.
                  _buildFailuresSection(context, data.report),
                  const SizedBox(height: 12),
                  _buildLogCard(context, data),
                  const SizedBox(height: 12),
                  // Everything enrichment-related (queue, cover jobs,
                  // iNaturalist cooldown, foreground service, its actions)
                  // lives in one section instead of five separate cards.
                  _buildEnrichmentSection(context, data, activeCooldown),
                  const SizedBox(height: 12),
                  _buildGeneralActionsCard(context),
                  const SizedBox(height: 12),
                  // Least actionable, most static — last. Reference-db
                  // status lives here too, as another static fact about
                  // this install rather than its own top-level section.
                  _buildAppInfoSection(context, data),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLastRefreshedRow(BuildContext context) {
    final lastRefreshedAt = _lastRefreshedAt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(
            Icons.sync,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            lastRefreshedAt == null
                ? '—'
                : context.loc.diagnosticsLastRefreshedAt(
                    MaterialLocalizations.of(
                      context,
                    ).formatTimeOfDay(TimeOfDay.fromDateTime(lastRefreshedAt)),
                  ),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(BuildContext context, _DiagnosticsPageData data) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            value: data.persistErrorLogs,
            title: Text(context.loc.diagnosticsPersistLogsTitle),
            subtitle: Text(context.loc.diagnosticsPersistLogsSubtitle),
            onChanged: _setPersistLogs,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text(context.loc.diagnosticsViewLog),
            onTap: _openLogViewer,
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(context.loc.diagnosticsClearLog),
            onTap: _clearLog,
          ),
        ],
      ),
    );
  }

  /// Everything enrichment-related — queue, cover jobs, iNaturalist
  /// cooldown, foreground service, and the two enrichment actions — as one
  /// section, rather than five separate cards a reader has to mentally
  /// group themselves.
  Widget _buildEnrichmentSection(
    BuildContext context,
    _DiagnosticsPageData data,
    HostCooldownSnapshot? cooldown,
  ) {
    final grouped = _groupWorkStateCounts(data.healthSnapshot);
    final coverJobs = data.healthSnapshot.coverJobs;
    return Card(
      child: Column(
        children: [
          _buildSectionHeader(
            context,
            context.loc.diagnosticsEnrichmentSectionTitle,
          ),
          ExpansionTile(
            initiallyExpanded: grouped.isNotEmpty,
            title: Text(context.loc.diagnosticsEnrichmentQueueTitle),
            children: grouped.isEmpty
                ? [_buildEmptyRow(context)]
                : grouped.entries
                      .map(
                        (entry) => ListTile(
                          dense: true,
                          title: Text(entry.key),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: entry.value
                                .map(
                                  (state) =>
                                      Text(_formatStateLine(context, state)),
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
                ? [_buildEmptyRow(context)]
                : coverJobs
                      .map(
                        (job) => ListTile(
                          dense: true,
                          title: Text('${job.deckId} • ${job.status.name}'),
                          subtitle: Text(
                            [
                              if (job.currentStage != null)
                                'stage ${job.currentStage!.name}',
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
              cooldown == null
                  ? context.loc.diagnosticsHostCooldownNone
                  : context.loc.diagnosticsHostCooldownActive(
                      cooldown.host,
                      _formatDuration(cooldown.remaining()),
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
            onTap: _resetStuckJobs,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.playlist_remove),
            title: Text(context.loc.diagnosticsCloseAllEnrichment),
            onTap: _closeAllEnrichment,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    _DiagnosticsPageData data,
    HostCooldownSnapshot? cooldown,
  ) {
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
                _MetricChip(
                  label: context.loc.diagnosticsMetricNetworkFailures,
                  value: '${data.report.totalNetworkFailureCount}',
                ),
                _MetricChip(
                  label: context.loc.diagnosticsMetricOutstandingEnrichmentWork,
                  value: '${data.healthSnapshot.outstandingWorkCount}',
                ),
                _MetricChip(
                  label: context.loc.diagnosticsMetricHostCooldownActive,
                  value: cooldown == null
                      ? context.loc.commonNo
                      : context.loc.commonYes,
                ),
                _MetricChip(
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

  /// Failures by host and the raw recent-failures list as one section —
  /// both are just different views over the same underlying network-failure
  /// data the "HTTP-Fehler" metric in Übersicht counts.
  Widget _buildFailuresSection(
    BuildContext context,
    LocalDiagnosticsReport report,
  ) {
    return Card(
      child: Column(
        children: [
          _buildSectionHeader(context, context.loc.diagnosticsFailuresTitle),
          ExpansionTile(
            initiallyExpanded: report.hostFailures.isNotEmpty,
            title: Text(context.loc.diagnosticsFailuresByHostTitle),
            children: report.hostFailures.isEmpty
                ? [_buildEmptyRow(context)]
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
                            _formatDateTime(context, summary.lastFailureAt),
                          ),
                        ),
                      )
                      .toList(growable: false),
          ),
          const Divider(height: 1),
          ExpansionTile(
            title: Text(context.loc.diagnosticsRecentFailuresTitle),
            children: report.recentFailures.isEmpty
                ? [_buildEmptyRow(context)]
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
                              '${failure.method} ${_requestUrl(failure)}',
                              if (failure.message != null) failure.message!,
                            ].join('\n'),
                          ),
                          trailing: Text(
                            _formatDateTime(context, failure.createdAt),
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

  /// The full request URL (including query string) is captured in
  /// [LocalDiagnosticsNetworkFailureRecord.details]`['requestUrl']` by
  /// [LocalDiagnostics]; [LocalDiagnosticsNetworkFailureRecord.urlPath] only
  /// carries the path, which is all that survives if [details] is ever
  /// empty (e.g. legacy rows).
  String _requestUrl(LocalDiagnosticsNetworkFailureRecord failure) {
    return failure.details['requestUrl'] as String? ?? failure.urlPath;
  }

  /// App info plus reference-db status as one section — both are static
  /// facts about this install rather than actionable diagnostics, so they
  /// don't need separate top-level cards.
  Widget _buildAppInfoSection(BuildContext context, _DiagnosticsPageData data) {
    final status = data.referenceDbStatus;
    final referenceDbSubtitle = !status.fileExists
        ? context.loc.diagnosticsReferenceDbNotInstalled
        : [
            'v${status.installedVersion ?? '-'}',
            'schema ${status.installedSchemaVersion ?? '-'}/${status.supportedSchemaVersion}',
            if (status.fileSizeBytes != null)
              _formatBytes(status.fileSizeBytes!),
            if (status.fileModifiedAt != null)
              _formatDateTime(
                context,
                status.fileModifiedAt!,
              ).replaceAll('\n', ' '),
          ].join(' • ');
    return Card(
      child: Column(
        children: [
          _buildSectionHeader(context, context.loc.diagnosticsAppInfoTitle),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${data.packageInfo.appName} ${data.packageInfo.version} '
                  '(${data.packageInfo.buildNumber})',
                ),
                Text(
                  '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: Text(context.loc.diagnosticsReferenceDbTitle),
            subtitle: Text(referenceDbSubtitle),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralActionsCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: _isCheckingDeckUpdates
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync_outlined),
            title: Text(context.loc.diagnosticsCheckDeckUpdatesNow),
            onTap: _isCheckingDeckUpdates ? null : _checkDeckCatalogUpdatesNow,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: Text(context.loc.diagnosticsResetAllSettings),
            onTap: _resetAllSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(context.loc.diagnosticsNoData),
      ),
    );
  }

  Map<String, List<EnrichmentWorkStateCount>> _groupWorkStateCounts(
    EnrichmentHealthSnapshot snapshot,
  ) {
    final grouped = <String, List<EnrichmentWorkStateCount>>{};
    for (final entry in snapshot.workStateCounts) {
      grouped.putIfAbsent(entry.label, () => []).add(entry);
    }
    for (final states in grouped.values) {
      states.sort((left, right) => left.state.compareTo(right.state));
    }
    final sortedKeys = grouped.keys.toList()..sort();
    return {for (final key in sortedKeys) key: grouped[key]!};
  }

  String _formatStateLine(
    BuildContext context,
    EnrichmentWorkStateCount state,
  ) {
    final base = '${state.state}: ${state.count}';
    final nextAttemptAt = state.nextAttemptAt;
    if (state.state != 'retryScheduled' || nextAttemptAt == null) {
      return base;
    }
    final remaining = nextAttemptAt.difference(DateTime.now());
    final eta = remaining.isNegative
        ? context.loc.diagnosticsNextRetryDue
        : context.loc.diagnosticsNextRetryIn(_formatDuration(remaining));
    return '$base — $eta';
  }

  Future<_DiagnosticsPageData> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final persistence = LogDiagnosticsPersistence(prefs, logFile: _logFile);
    final results = await Future.wait([
      _repository.loadReport(),
      _healthSnapshotService.loadSnapshot(),
      _referenceDbProvisioner.currentStatus(),
      _queueService.isForegroundServiceRunning,
      PackageInfo.fromPlatform(),
      _decksService.getTotalDistinctSpeciesCount(),
    ]);
    _lastRefreshedAt = DateTime.now();
    return _DiagnosticsPageData(
      report: results[0] as LocalDiagnosticsReport,
      healthSnapshot: results[1] as EnrichmentHealthSnapshot,
      referenceDbStatus: results[2] as ReferenceDbStatus,
      foregroundServiceRunning: results[3] as bool,
      packageInfo: results[4] as PackageInfo,
      persistErrorLogs: persistence.isEnabled,
      totalSpeciesCount: results[5] as int,
    );
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
    _isRefreshing = false;
  }

  Future<void> _setPersistLogs(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final persistence = LogDiagnosticsPersistence(prefs, logFile: _logFile);
    await persistence.setEnabled(enabled);
    await _refresh();
  }

  void _openLogViewer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiagnosticsLogViewerPage(logFile: _logFile),
      ),
    );
  }

  Future<void> _clearLog() async {
    await _logFile.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.loc.diagnosticsLogCleared)));
  }

  Future<void> _resetStuckJobs() async {
    final recovered = await _healthSnapshotService.recoverStuckWork();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.loc.diagnosticsResetStuckJobsDone(recovered)),
      ),
    );
    await _refresh();
  }

  Future<void> _checkDeckCatalogUpdatesNow() async {
    setState(() => _isCheckingDeckUpdates = true);
    try {
      await _deckUpdateService.checkForUpdates(force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.loc.diagnosticsCheckDeckUpdatesDone(
              _deckUpdateService.availableUpdateCount,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCheckingDeckUpdates = false);
    }
  }

  Future<void> _closeAllEnrichment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          dialogContext.loc.diagnosticsCloseAllEnrichmentConfirmTitle,
        ),
        content: Text(
          dialogContext.loc.diagnosticsCloseAllEnrichmentConfirmBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.loc.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.loc.diagnosticsCloseAllEnrichment),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await _healthSnapshotService.closeAllOutstandingWork();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.loc.diagnosticsCloseAllEnrichmentDone(
            result.removedWorkItems,
            result.cancelledJobs,
          ),
        ),
      ),
    );
    await _refresh();
  }

  /// Clears every locally stored preference app-wide — tutorial "seen"
  /// flags, notification schedule, developer-mode unlock, the reference
  /// database's cached version, etc. Deliberately a blunt `prefs.clear()`
  /// rather than deleting individual keys: this is a developer/support tool
  /// for reproducing first-run behavior (e.g. a tutorial that didn't show),
  /// not a targeted per-feature reset.
  Future<void> _resetAllSettings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.loc.diagnosticsResetAllSettingsConfirmTitle),
        content: Text(dialogContext.loc.diagnosticsResetAllSettingsConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.loc.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.loc.diagnosticsResetAllSettings),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.loc.diagnosticsResetAllSettingsDone)),
    );
    await _refresh();
  }

  Future<void> _shareReport() async {
    final data = await _future;
    if (data == null) return;
    await SharePlus.instance.share(ShareParams(text: _buildReportText(data)));
  }

  Future<void> _copyReport() async {
    final data = await _future;
    if (data == null || !mounted) return;
    await Clipboard.setData(ClipboardData(text: _buildReportText(data)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.loc.diagnosticsReportCopied)),
    );
  }

  String _buildReportText(_DiagnosticsPageData data) {
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
    final grouped = _groupWorkStateCounts(data.healthSnapshot);
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
        'stage=${job.currentStage?.name ?? '-'} retries=${job.retryCount}',
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
        '${failure.method} ${_requestUrl(failure)} '
        '${failure.statusCode ?? failure.exceptionType ?? '-'} '
        '${failure.message ?? ''}',
      );
    }
    return buffer.toString();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${duration.inSeconds}s';
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  String _formatDateTime(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatShortDate(local);
    final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return '$date\n$time';
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _DiagnosticsPageData {
  final LocalDiagnosticsReport report;
  final EnrichmentHealthSnapshot healthSnapshot;
  final ReferenceDbStatus referenceDbStatus;
  final bool foregroundServiceRunning;
  final PackageInfo packageInfo;
  final bool persistErrorLogs;
  final int totalSpeciesCount;

  const _DiagnosticsPageData({
    required this.report,
    required this.healthSnapshot,
    required this.referenceDbStatus,
    required this.foregroundServiceRunning,
    required this.packageInfo,
    required this.persistErrorLogs,
    required this.totalSpeciesCount,
  });
}
