import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'enrichment_service.dart';

enum INatEnrichmentPhase { idle, base, inat, names }

class DeckEnrichmentInfo {
  final bool isActive;
  final DateTime? lastCompletedAt;

  const DeckEnrichmentInfo({
    required this.isActive,
    required this.lastCompletedAt,
  });

  @override
  bool operator ==(Object other) {
    return other is DeckEnrichmentInfo &&
        other.isActive == isActive &&
        other.lastCompletedAt == lastCompletedAt;
  }

  @override
  int get hashCode => Object.hash(isActive, lastCompletedAt);
}

class INatEnrichmentStatus {
  final bool isRunning;
  final INatEnrichmentPhase phase;
  final int completed;
  final int total;

  const INatEnrichmentStatus({
    required this.isRunning,
    required this.phase,
    required this.completed,
    required this.total,
  });

  static const idle = INatEnrichmentStatus(
    isRunning: false,
    phase: INatEnrichmentPhase.idle,
    completed: 0,
    total: 0,
  );
}

class INatEnrichmentQueueService extends ChangeNotifier {
  static const _backgroundINatMaxConcurrent = 1;
  static const _backgroundINatRequestSpacing = Duration(milliseconds: 1100);
  static const _completedAtPreferencePrefix = 'inat_enrichment_completed_at.';

  final EnrichmentService _enrichmentService;
  final SharedPreferences? _preferences;
  final Set<String> _pendingBaseDeckIds = <String>{};
  final Set<String> _pendingPrimaryINatPhotoDeckIds = <String>{};
  final Set<String> _pendingBackfillINatPhotoDeckIds = <String>{};
  final Set<String> _pendingINatCommonNameDeckIds = <String>{};
  final Set<String> _activeDeckIds = <String>{};
  final Map<String, DateTime> _lastCompletedAtByDeckId = <String, DateTime>{};

  INatEnrichmentStatus _status = INatEnrichmentStatus.idle;
  Future<void>? _runner;

  INatEnrichmentQueueService(
    this._enrichmentService, {
    SharedPreferences? preferences,
  }) : _preferences = preferences {
    _restoreCompletionTimestamps();
  }

  INatEnrichmentStatus get status => _status;

  DeckEnrichmentInfo deckInfo(String deckId) {
    return DeckEnrichmentInfo(
      isActive: _activeDeckIds.contains(deckId),
      lastCompletedAt: _lastCompletedAtByDeckId[deckId],
    );
  }

  Future<void> scheduleDeckEnrichment(
    List<String> deckIds, {
    bool includeINatPhotos = true,
    bool includeCommonNames = true,
  }) {
    final normalizedDeckIds = deckIds
        .map((deckId) => deckId.trim())
        .where((deckId) => deckId.isNotEmpty)
        .toSet();
    if (normalizedDeckIds.isEmpty) {
      return Future.value();
    }

    _pendingBaseDeckIds.addAll(normalizedDeckIds);

    if (includeINatPhotos) {
      _pendingPrimaryINatPhotoDeckIds.addAll(normalizedDeckIds);
      _pendingBackfillINatPhotoDeckIds.addAll(normalizedDeckIds);
    }

    if (includeCommonNames) {
      _pendingINatCommonNameDeckIds.addAll(normalizedDeckIds);
    }

    _runner ??= _runQueue();
    return _runner!;
  }

  Future<void> _runQueue() async {
    try {
      while (true) {
        final baseDeckIds = _drain(_pendingBaseDeckIds);
        final primaryPhotoDeckIds = _drain(_pendingPrimaryINatPhotoDeckIds);
        final commonNameDeckIds = _drain(_pendingINatCommonNameDeckIds);
        final backfillPhotoDeckIds = _drain(_pendingBackfillINatPhotoDeckIds);

        if (baseDeckIds.isEmpty &&
            primaryPhotoDeckIds.isEmpty &&
            commonNameDeckIds.isEmpty &&
            backfillPhotoDeckIds.isEmpty) {
          break;
        }

        final cycleDeckIds = <String>{
          ...baseDeckIds,
          ...primaryPhotoDeckIds,
          ...commonNameDeckIds,
          ...backfillPhotoDeckIds,
        };
        _activeDeckIds
          ..clear()
          ..addAll(cycleDeckIds);
        notifyListeners();

        await _runBaseStage(baseDeckIds);
        await _runPrimaryINatPhotoStage(primaryPhotoDeckIds);
        await _runCommonNameStage(commonNameDeckIds);
        await _runBackfillINatPhotoStage(backfillPhotoDeckIds);

        _markDecksCompleted(cycleDeckIds);
        _activeDeckIds.removeAll(cycleDeckIds);
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('iNat enrichment queue failed: $e');
      }
    } finally {
      _runner = null;
      _setStatus(INatEnrichmentStatus.idle);

      if (_hasPendingWork) {
        _runner = _runQueue();
      }
    }
  }

  Future<void> _runBaseStage(Set<String> deckIds) async {
    if (deckIds.isEmpty) return;

    try {
      await _enrichmentService.downloadBaseImagesForDecks(
        deckIds.toList(),
        onProgress: (completed, total) {
          _setStatus(
            INatEnrichmentStatus(
              isRunning: true,
              phase: INatEnrichmentPhase.base,
              completed: completed,
              total: total,
            ),
          );
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Base image background enrichment failed: $e');
      }
    }
  }

  Future<void> _runPrimaryINatPhotoStage(Set<String> deckIds) async {
    if (deckIds.isEmpty) return;

    try {
      await _enrichmentService.fetchINatPhotosForDecks(
        deckIds.toList(),
        primaryOnly: true,
        prioritizeSpeciesWithoutImages: true,
        maxConcurrent: _backgroundINatMaxConcurrent,
        requestSpacing: _backgroundINatRequestSpacing,
        onProgress: (completed, total) {
          _setStatus(
            INatEnrichmentStatus(
              isRunning: true,
              phase: INatEnrichmentPhase.inat,
              completed: completed,
              total: total,
            ),
          );
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Primary iNat photo background enrichment failed: $e');
      }
    }
  }

  Future<void> _runCommonNameStage(Set<String> deckIds) async {
    if (deckIds.isEmpty) return;

    try {
      await _enrichmentService.fetchINatCommonNamesForDecks(
        deckIds.toList(),
        maxConcurrent: _backgroundINatMaxConcurrent,
        requestSpacing: _backgroundINatRequestSpacing,
        onProgress: (completed, total) {
          _setStatus(
            INatEnrichmentStatus(
              isRunning: true,
              phase: INatEnrichmentPhase.names,
              completed: completed,
              total: total,
            ),
          );
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('iNat common-name background enrichment failed: $e');
      }
    }
  }

  Future<void> _runBackfillINatPhotoStage(Set<String> deckIds) async {
    if (deckIds.isEmpty) return;

    try {
      await _enrichmentService.backfillINatPhotosForDecks(
        deckIds.toList(),
        maxConcurrent: _backgroundINatMaxConcurrent,
        requestSpacing: _backgroundINatRequestSpacing,
        onProgress: (completed, total) {
          _setStatus(
            INatEnrichmentStatus(
              isRunning: true,
              phase: INatEnrichmentPhase.inat,
              completed: completed,
              total: total,
            ),
          );
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('iNat photo backfill failed: $e');
      }
    }
  }

  Set<String> _drain(Set<String> source) {
    final snapshot = Set<String>.from(source);
    source.clear();
    return snapshot;
  }

  bool get _hasPendingWork =>
      _pendingBaseDeckIds.isNotEmpty ||
      _pendingPrimaryINatPhotoDeckIds.isNotEmpty ||
      _pendingBackfillINatPhotoDeckIds.isNotEmpty ||
      _pendingINatCommonNameDeckIds.isNotEmpty;

  void _restoreCompletionTimestamps() {
    final preferences = _preferences;
    if (preferences == null) return;

    for (final key in preferences.getKeys()) {
      if (!key.startsWith(_completedAtPreferencePrefix)) continue;
      final value = preferences.getInt(key);
      if (value == null) continue;

      final deckId = key.substring(_completedAtPreferencePrefix.length);
      _lastCompletedAtByDeckId[deckId] = DateTime.fromMillisecondsSinceEpoch(
        value,
      );
    }
  }

  void _markDecksCompleted(Set<String> deckIds) {
    if (deckIds.isEmpty) return;

    final completedAt = DateTime.now();
    for (final deckId in deckIds) {
      _lastCompletedAtByDeckId[deckId] = completedAt;
      _preferences?.setInt(
        '$_completedAtPreferencePrefix$deckId',
        completedAt.millisecondsSinceEpoch,
      );
    }
  }

  void _setStatus(INatEnrichmentStatus nextStatus) {
    final hasChanged =
        _status.isRunning != nextStatus.isRunning ||
        _status.phase != nextStatus.phase ||
        _status.completed != nextStatus.completed ||
        _status.total != nextStatus.total;
    if (!hasChanged) return;

    _status = nextStatus;
    notifyListeners();
  }
}
