import 'package:discere/learning/decks/deck_view_model.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The existing decks in the "add to deck" sheet, each a target to add the
/// species to; locked while [isAdding].
class AddToDeckList extends StatelessWidget {
  final Future<List<DeckViewModel>> decks;
  final ScrollController scrollController;
  final bool isAdding;
  final ValueChanged<DeckViewModel> onPick;

  const AddToDeckList({
    required this.decks,
    required this.scrollController,
    required this.isAdding,
    required this.onPick,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<DeckViewModel>>(
      future: decks,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _message(
            context,
            context.loc.errorWithDetail(
              context.loc.describeError(snapshot.error),
            ),
          );
        }
        final decks = snapshot.data ?? const [];
        if (decks.isEmpty) {
          return _message(context, context.loc.addToDeckSheetNoExistingDecks);
        }

        return AbsorbPointer(
          absorbing: isAdding,
          child: ListView.builder(
            controller: scrollController,
            itemCount: decks.length,
            itemBuilder: (context, index) {
              final deck = decks[index];
              return ListTile(
                key: ValueKey('add_to_deck_target_${deck.stored.id}'),
                leading: Icon(
                  Icons.style_outlined,
                  color: colorScheme.onSurfaceVariant,
                ),
                title: Text(deck.stored.name),
                trailing: const Icon(Icons.add),
                onTap: () => onPick(deck),
              );
            },
          ),
        );
      },
    );
  }

  Widget _message(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
