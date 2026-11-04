import 'dart:async';

import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/decks/add_to_deck/add_to_deck_list.dart';
import 'package:discere/learning/decks/create_deck_page.dart';
import 'package:discere/learning/decks/deck_view_model.dart';
import 'package:discere/learning/import/inat_download_dialog.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/notification_permission_dialog.dart';
import 'package:discere/shared/ui/sheet_messenger.dart';
import 'package:discere/shared/util/failure_logging.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum _AddToDeckChoice { addedToExisting, createNew }

/// Opens the "add to deck" bottom sheet: pick an existing deck to add
/// [speciesIds] to directly, or create a new deck pre-filled with
/// [speciesNames]. Resolves to `true` once species actually ended up in a
/// deck (existing or newly created), `false` if the flow was cancelled at
/// any point — callers use this to decide whether to navigate back to
/// wherever the add-to-deck flow started from.
Future<bool> showAddToDeckSheet(
  BuildContext context, {
  required Set<String> speciesIds,
  required Set<String> speciesNames,
}) async {
  final choice = await showModalBottomSheet<_AddToDeckChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        AddToDeckSheet(speciesIds: speciesIds, speciesNames: speciesNames),
  );

  switch (choice) {
    case _AddToDeckChoice.addedToExisting:
      return true;
    case _AddToDeckChoice.createNew:
      if (!context.mounted) return false;
      final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => CreateDeckPage(initialSpeciesNames: speciesNames),
        ),
      );
      return created ?? false;
    case null:
      return false;
  }
}

class AddToDeckSheet extends StatefulWidget {
  final Set<String> speciesIds;
  final Set<String> speciesNames;

  const AddToDeckSheet({
    required this.speciesIds,
    required this.speciesNames,
    super.key,
  });

  @override
  State<AddToDeckSheet> createState() => _AddToDeckSheetState();
}

class _AddToDeckSheetState extends State<AddToDeckSheet> {
  static final _log = Logger.forType(AddToDeckSheet);

  /// See [SheetMessenger].
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final Future<List<DeckViewModel>> _decksFuture;
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    _decksFuture = Provider.of<DecksService>(
      context,
      listen: false,
    ).getAllDecks().warnOnFailure(_log, 'Deck list load');
  }

  Future<void> _addToExisting(DeckViewModel deck) async {
    if (_isAdding) return;
    setState(() => _isAdding = true);
    final decksService = Provider.of<DecksService>(context, listen: false);
    final enrichmentQueue = Provider.of<INatEnrichmentQueueService>(
      context,
      listen: false,
    );
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final loc = context.loc;
    final deckId = deck.stored.id!;
    try {
      await decksService.addSpeciesToDeck(deckId, widget.speciesIds);
    } catch (error, stackTrace) {
      _log.warn(
        'Adding to a deck failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      // Unlocked and left open, to try again.
      setState(() => _isAdding = false);
      SheetMessenger.show(
        _messengerKey,
        loc.addToDeckFailed(loc.describeError(error)),
      );
      return;
    }
    if (!mounted) return;
    await _offerINatEnrichment(enrichmentQueue, deckId);
    if (!mounted) return;
    navigator.pop(_AddToDeckChoice.addedToExisting);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          loc.addToDeckSuccess(widget.speciesIds.length, deck.stored.name),
        ),
      ),
    );
  }

  /// Mirrors the enrichment prompt shown right after creating a deck: the
  /// newly added species always get their bundled reference image, and the
  /// user is asked whether to also fetch iNaturalist photos and common names.
  Future<void> _offerINatEnrichment(
    INatEnrichmentQueueService enrichmentQueue,
    String deckId,
  ) async {
    unawaited(
      enrichmentQueue.scheduleDeckEnrichment(
        [deckId],
        includeINatPhotos: false,
        includeCommonNames: false,
      ),
    );
    final includeINat = await showINatDownloadDialog(context, [deckId]);
    if (includeINat && mounted) {
      await ensureNotificationPermission(context);
      unawaited(
        enrichmentQueue.scheduleDeckEnrichment(
          [deckId],
          includeINatPhotos: true,
          includeCommonNames: true,
        ),
      );
    }
  }

  void _createNewDeck() {
    Navigator.of(context).pop(_AddToDeckChoice.createNew);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return SheetMessenger(
          messengerKey: _messengerKey,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      context.loc.addToDeckSheetTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('add_to_deck_create_new'),
                leading: CircleAvatar(
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    Icons.create_new_folder_outlined,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                title: Text(context.loc.addToDeckSheetCreateNewDeck),
                onTap: _createNewDeck,
              ),
              const Divider(height: 1),
              Expanded(
                child: AddToDeckList(
                  decks: _decksFuture,
                  scrollController: scrollController,
                  isAdding: _isAdding,
                  onPick: _addToExisting,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
