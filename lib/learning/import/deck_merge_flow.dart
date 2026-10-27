import 'dart:async';

import 'package:discere/learning/import/deck_import_flow.dart';
import 'package:discere/learning/import/deck_merge_dialog.dart';
import 'package:discere/learning/import/deck_merge_progress_dialog.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_merge_service.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

final _log = Logger.scoped('DeckMergeFlow');

/// Whether a merge flow is under way, from planning to the end of the merge.
/// App-wide, because the deck card and the online tab can both start one:
/// a second merge of the same entry started before the first has imported
/// it would import it a second time.
bool _mergeFlowRunning = false;

/// Merges the catalog [entry] into the user's decks once the user has
/// confirmed what it does — the one flow behind both the "replaced by" hint
/// on a superseded deck and the online tab's entry that supersedes local
/// decks. Resolves to whether it merged; declining changes nothing, and the
/// hint stays.
///
/// [catalog] is the catalog [entry] comes from: whether a superseded deck
/// goes depends on every entry that supersedes it.
///
/// Resolves to `false` straight away while another merge flow runs.
Future<bool> runDeckMergeFlow(
  BuildContext context, {
  required CreateDeck entry,
  required List<CreateDeck> catalog,
}) async {
  if (_mergeFlowRunning) return false;
  _mergeFlowRunning = true;
  try {
    return await _runDeckMergeFlow(context, entry: entry, catalog: catalog);
  } finally {
    _mergeFlowRunning = false;
  }
}

Future<bool> _runDeckMergeFlow(
  BuildContext context, {
  required CreateDeck entry,
  required List<CreateDeck> catalog,
}) async {
  final mergeService = context.read<DeckMergeService>();
  final updateService = context.read<DeckUpdateService>();
  // What follows the merge is shown from the navigator: the deck card that
  // may have started it is gone once its deck is deleted.
  final navigator = Navigator.of(context);
  final host = navigator.context;
  try {
    final plan = await mergeService.plan(entry, catalog);
    if (!context.mounted || !await showDeckMergeDialog(context, plan)) {
      return false;
    }
    // Asked before the merge starts, not within it: the merge counts as a
    // write sequence for the in-app restart, which a dialog must never be.
    // The progress dialog stays outside it for the same reason.
    final merged = await _withProgressDialog(
      navigator,
      () => mergeService.merge(plan),
    );
    await updateService.reconcileWithLocalDecks();
    final imported = merged.importResult;
    if (imported != null && host.mounted) {
      await offerImportDownload(host, imported);
    }
    return true;
  } catch (e, stackTrace) {
    _log.warn('Merging decks failed', error: e, stackTrace: stackTrace);
    if (host.mounted) {
      ScaffoldMessenger.of(host).showSnackBar(
        SnackBar(
          content: Text(host.loc.deckMergeError(host.loc.describeError(e))),
        ),
      );
    }
    return false;
  }
}

/// Runs [work] under [DeckMergeProgressDialog], which goes once it is done,
/// however it ends.
Future<T> _withProgressDialog<T>(
  NavigatorState navigator,
  Future<T> Function() work,
) async {
  final route = DialogRoute<void>(
    context: navigator.context,
    barrierDismissible: false,
    builder: (_) => const DeckMergeProgressDialog(),
  );
  unawaited(navigator.push(route));
  try {
    return await work();
  } finally {
    if (route.isActive) navigator.removeRoute(route);
  }
}
