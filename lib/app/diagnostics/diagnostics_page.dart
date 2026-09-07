import 'dart:async';

import 'package:discere/app/diagnostics/diagnostics_actions.dart';
import 'package:discere/app/diagnostics/diagnostics_log_viewer_page.dart';
import 'package:discere/app/diagnostics/diagnostics_page_data.dart';
import 'package:discere/app/diagnostics/diagnostics_report_text.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_confirm_dialogs.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_section_list.dart';
import 'package:discere/diagnostics/repository/local_diagnostics_repository.dart';
import 'package:discere/diagnostics/service/diagnostics_log_file.dart';
import 'package:discere/diagnostics/service/log_diagnostics_persistence.dart';
import 'package:discere/enrichment/queue/service/enrichment_health_snapshot_service.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Developer/support view over what the app has recorded about itself.
///
/// The sections live in `widgets/` — this class keeps only what a widget
/// cannot: the provider lookups, the one-shot load, and the actions, all of
/// which are async work bound to `setState`/`mounted`.
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
  late final EnrichmentHealthSnapshotService _healthSnapshotService;
  late final DiagnosticsLogFile _logFile;
  late final ReferenceDatabaseProvisioner _referenceDbProvisioner;
  late final INatEnrichmentQueueService _queueService;
  late final DeckUpdateService _deckUpdateService;
  late final DecksService _decksService;
  Future<DiagnosticsPageData>? _future;
  bool _isRefreshing = false;
  bool _isCheckingDeckUpdates = false;
  DateTime? _lastRefreshedAt;

  @override
  void initState() {
    super.initState();
    _logFile = Provider.of<DiagnosticsLogFile>(context, listen: false);
    _healthSnapshotService = Provider.of<EnrichmentHealthSnapshotService>(
      context,
      listen: false,
    );
    _referenceDbProvisioner = Provider.of<ReferenceDatabaseProvisioner>(
      context,
      listen: false,
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
        child: FutureBuilder<DiagnosticsPageData>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            // Ordered by how actionable each section is: the dashboard
            // first, static facts about the install last.
            return RefreshIndicator(
              onRefresh: _refresh,
              child: DiagnosticsSectionList(
                data: data,
                cooldown: activeCooldown,
                lastRefreshedAt: _lastRefreshedAt,
                isCheckingDeckUpdates: _isCheckingDeckUpdates,
                actions: DiagnosticsActions(
                  setPersistLogs: _setPersistLogs,
                  openLogViewer: _openLogViewer,
                  clearLog: _clearLog,
                  resetStuckJobs: _resetStuckJobs,
                  closeAllEnrichment: _closeAllEnrichment,
                  checkDeckUpdates: _checkDeckCatalogUpdatesNow,
                  resetAllSettings: _resetAllSettings,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<DiagnosticsPageData> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = await DiagnosticsPageData.load(
      repository: _repository,
      healthSnapshotService: _healthSnapshotService,
      referenceDbProvisioner: _referenceDbProvisioner,
      queueService: _queueService,
      decksService: _decksService,
      logPersistence: LogDiagnosticsPersistence(prefs, logFile: _logFile),
    );
    _lastRefreshedAt = DateTime.now();
    return data;
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

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    _showSnackBar(context.loc.diagnosticsLogCleared);
  }

  Future<void> _resetStuckJobs() async {
    final recovered = await _healthSnapshotService.recoverStuckWork();
    if (!mounted) return;
    _showSnackBar(context.loc.diagnosticsResetStuckJobsDone(recovered));
    await _refresh();
  }

  Future<void> _checkDeckCatalogUpdatesNow() async {
    setState(() => _isCheckingDeckUpdates = true);
    try {
      await _deckUpdateService.checkForUpdates(force: true);
      if (!mounted) return;
      _showSnackBar(
        context.loc.diagnosticsCheckDeckUpdatesDone(
          _deckUpdateService.availableUpdateCount,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCheckingDeckUpdates = false);
    }
  }

  Future<void> _closeAllEnrichment() async {
    if (!await showCloseAllEnrichmentConfirmation(context) || !mounted) return;
    final result = await _healthSnapshotService.closeAllOutstandingWork();
    if (!mounted) return;
    _showSnackBar(
      context.loc.diagnosticsCloseAllEnrichmentDone(
        result.removedWorkItems,
        result.cancelledJobs,
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
    if (!await showResetAllSettingsConfirmation(context) || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    _showSnackBar(context.loc.diagnosticsResetAllSettingsDone);
    await _refresh();
  }

  Future<void> _shareReport() async {
    final data = await _future;
    if (data == null) return;
    await SharePlus.instance.share(
      ShareParams(text: buildDiagnosticsReportText(data)),
    );
  }

  Future<void> _copyReport() async {
    final data = await _future;
    if (data == null || !mounted) return;
    await Clipboard.setData(
      ClipboardData(text: buildDiagnosticsReportText(data)),
    );
    if (!mounted) return;
    _showSnackBar(context.loc.diagnosticsReportCopied);
  }
}
