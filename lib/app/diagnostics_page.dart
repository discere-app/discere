import 'dart:convert';

import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/repository/local_diagnostics_repository.dart';
import 'package:discere/shared/service/log_diagnostics_persistence.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  final LocalDiagnosticsRepository _repository =
      const LocalDiagnosticsRepository();
  Future<_DiagnosticsPageData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.loc.diagnosticsTitle),
        actions: [
          IconButton(
            tooltip: context.loc.diagnosticsCopyReport,
            onPressed: _copyReport,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: context.loc.diagnosticsCopyJson,
            onPressed: _copyJsonReport,
            icon: const Icon(Icons.data_object_outlined),
          ),
        ],
      ),
      body: FutureBuilder<_DiagnosticsPageData>(
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
                Card(
                  child: SwitchListTile(
                    value: data.persistErrorLogs,
                    title: Text(context.loc.diagnosticsPersistLogsTitle),
                    subtitle: Text(context.loc.diagnosticsPersistLogsSubtitle),
                    onChanged: (value) => _setPersistLogs(value),
                  ),
                ),
                const SizedBox(height: 12),
                _buildSummaryCard(context, data.report),
                const SizedBox(height: 12),
                _buildHostFailuresCard(context, data.report),
                const SizedBox(height: 12),
                _buildStageCard(context, data.report),
                const SizedBox(height: 12),
                _buildRunsCard(context, data.report),
                const SizedBox(height: 12),
                _buildRecentFailuresCard(context, data.report),
                const SizedBox(height: 12),
                _buildRecentLogsCard(context, data.report),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    LocalDiagnosticsReport report,
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
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricChip(
                  label: context.loc.diagnosticsMetricRuns,
                  value: '${report.totalRunCount}',
                ),
                _MetricChip(
                  label: context.loc.diagnosticsMetricAverageRunDuration,
                  value: _formatDuration(report.averageRunDuration),
                ),
                _MetricChip(
                  label: context.loc.diagnosticsMetricRetries,
                  value: '${report.totalRetryCount}',
                ),
                _MetricChip(
                  label: context.loc.diagnosticsMetricNetworkFailures,
                  value: '${report.totalNetworkFailureCount}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostFailuresCard(
    BuildContext context,
    LocalDiagnosticsReport report,
  ) {
    return Card(
      child: ExpansionTile(
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
                        '${summary.retryableFailureCount}/${summary.failureCount} ${context.loc.diagnosticsMetricRetries.toLowerCase()}',
                      ),
                      trailing: Text(
                        _formatDateTime(context, summary.lastFailureAt),
                      ),
                    ),
                  )
                  .toList(growable: false),
      ),
    );
  }

  Widget _buildStageCard(BuildContext context, LocalDiagnosticsReport report) {
    return Card(
      child: ExpansionTile(
        title: Text(context.loc.diagnosticsStagesTitle),
        children: report.stageSummaries.isEmpty
            ? [_buildEmptyRow(context)]
            : report.stageSummaries
                  .map(
                    (summary) => ListTile(
                      dense: true,
                      title: Text(summary.stage),
                      subtitle: Text(
                        'start ${summary.startedCount} • ok ${summary.successCount} • yield ${summary.yieldedCount}',
                      ),
                      trailing: Text(
                        '${context.loc.diagnosticsMetricRetries}: ${summary.retryCount}',
                      ),
                    ),
                  )
                  .toList(growable: false),
      ),
    );
  }

  Widget _buildRunsCard(BuildContext context, LocalDiagnosticsReport report) {
    return Card(
      child: ExpansionTile(
        title: Text(context.loc.diagnosticsRecentRunsTitle),
        children: report.recentRuns.isEmpty
            ? [_buildEmptyRow(context)]
            : report.recentRuns
                  .take(10)
                  .map(
                    (run) => ListTile(
                      dense: true,
                      title: Text(
                        '${run.runnerKind} • ${_formatDateTime(context, run.startedAt)}',
                      ),
                      subtitle: Text(
                        '${context.loc.diagnosticsMetricProcessedStages}: ${run.processedStages} • '
                        '${context.loc.diagnosticsMetricRetries}: ${run.retryCount} • '
                        '${context.loc.diagnosticsMetricFailures}: ${run.networkFailureCount}',
                      ),
                      trailing: Text(_formatDurationMillis(run.durationMs)),
                    ),
                  )
                  .toList(growable: false),
      ),
    );
  }

  Widget _buildRecentFailuresCard(
    BuildContext context,
    LocalDiagnosticsReport report,
  ) {
    return Card(
      child: ExpansionTile(
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
                          if (failure.stage != null) failure.stage!,
                          '${failure.method} ${failure.urlPath}',
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
    );
  }

  Widget _buildRecentLogsCard(
    BuildContext context,
    LocalDiagnosticsReport report,
  ) {
    return Card(
      child: ExpansionTile(
        title: Text(context.loc.diagnosticsRecentLogsTitle),
        children: report.recentLogs.isEmpty
            ? [_buildEmptyRow(context)]
            : report.recentLogs
                  .take(20)
                  .map(
                    (entry) => ListTile(
                      dense: true,
                      title: Text(
                        '${entry.level.toUpperCase()} • ${entry.scope}',
                      ),
                      subtitle: Text(entry.message),
                      trailing: Text(
                        _formatDateTime(context, entry.createdAt),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  )
                  .toList(growable: false),
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

  Future<_DiagnosticsPageData> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final persistence = LogDiagnosticsPersistence(prefs);
    final report = await _repository.loadReport();
    return _DiagnosticsPageData(
      report: report,
      persistErrorLogs: persistence.isEnabled,
    );
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _setPersistLogs(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final persistence = LogDiagnosticsPersistence(prefs);
    await persistence.setEnabled(enabled);
    await _refresh();
  }

  Future<void> _copyReport() async {
    final data = await _future;
    if (data == null || !mounted) return;
    final report = data.report;
    final buffer = StringBuffer()
      ..writeln('runs=${report.totalRunCount}')
      ..writeln('avgRun=${_formatDuration(report.averageRunDuration)}')
      ..writeln('retries=${report.totalRetryCount}')
      ..writeln('networkFailures=${report.totalNetworkFailureCount}')
      ..writeln()
      ..writeln('hosts:');
    for (final host in report.hostFailures.take(8)) {
      buffer.writeln(
        '- ${host.host}: ${host.failureCount} (${host.retryableFailureCount} retryable)',
      );
    }
    buffer.writeln();
    buffer.writeln('runs:');
    for (final run in report.recentRuns.take(8)) {
      buffer.writeln(
        '- ${run.runnerKind} ${run.runId}: stages=${run.processedStages}, retries=${run.retryCount}, failures=${run.networkFailureCount}, duration=${_formatDurationMillis(run.durationMs)}',
      );
    }
    buffer.writeln();
    buffer.writeln('logs:');
    for (final entry in report.recentLogs.take(20)) {
      buffer.writeln(
        '- ${entry.level.toUpperCase()} ${entry.scope} @ ${entry.createdAt.toIso8601String()}: ${entry.message}',
      );
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.loc.diagnosticsReportCopied)),
    );
  }

  Future<void> _copyJsonReport() async {
    final data = await _future;
    if (data == null || !mounted) return;
    final report = data.report;
    final payload = <String, Object?>{
      'runs': report.totalRunCount,
      'avgRunMs': report.averageRunDuration?.inMilliseconds,
      'retries': report.totalRetryCount,
      'networkFailures': report.totalNetworkFailureCount,
      'hosts': report.hostFailures
          .map(
            (host) => {
              'host': host.host,
              'failureCount': host.failureCount,
              'retryableFailureCount': host.retryableFailureCount,
              'lastFailureAt': host.lastFailureAt.toIso8601String(),
            },
          )
          .toList(growable: false),
      'stages': report.stageSummaries
          .map(
            (stage) => {
              'stage': stage.stage,
              'startedCount': stage.startedCount,
              'successCount': stage.successCount,
              'yieldedCount': stage.yieldedCount,
              'retryCount': stage.retryCount,
              'failedPermanentCount': stage.failedPermanentCount,
            },
          )
          .toList(growable: false),
      'recentRuns': report.recentRuns
          .map(
            (run) => {
              'runId': run.runId,
              'startedAt': run.startedAt.toIso8601String(),
              'finishedAt': run.finishedAt?.toIso8601String(),
              'runnerKind': run.runnerKind,
              'durationMs': run.durationMs,
              'processedStages': run.processedStages,
              'retryCount': run.retryCount,
              'networkFailureCount': run.networkFailureCount,
              'pendingWorkAtEnd': run.pendingWorkAtEnd,
            },
          )
          .toList(growable: false),
      'recentFailures': report.recentFailures
          .map(
            (failure) => {
              'createdAt': failure.createdAt.toIso8601String(),
              'host': failure.host,
              'method': failure.method,
              'urlPath': failure.urlPath,
              'stage': failure.stage,
              'statusCode': failure.statusCode,
              'exceptionType': failure.exceptionType,
              'message': failure.message,
              'retryable': failure.retryable,
            },
          )
          .toList(growable: false),
      'recentLogs': report.recentLogs
          .map(
            (entry) => {
              'createdAt': entry.createdAt.toIso8601String(),
              'level': entry.level,
              'scope': entry.scope,
              'message': entry.message,
            },
          )
          .toList(growable: false),
    };
    final jsonText = const JsonEncoder.withIndent('  ').convert(payload);
    await Clipboard.setData(ClipboardData(text: jsonText));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.loc.diagnosticsJsonCopied)));
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '—';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${duration.inSeconds}s';
  }

  String _formatDurationMillis(int? durationMs) {
    if (durationMs == null) return '—';
    return _formatDuration(Duration(milliseconds: durationMs));
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
  final bool persistErrorLogs;

  const _DiagnosticsPageData({
    required this.report,
    required this.persistErrorLogs,
  });
}
