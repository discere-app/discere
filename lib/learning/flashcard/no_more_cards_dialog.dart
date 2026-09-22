import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Shown when a review session reaches its last card and the deck has no
/// uninitialized cards left to offer — everything due has been reviewed.
///
/// Closes only itself. Leaving the deck afterwards is the caller's decision
/// and belongs to the caller's navigator: a second `pop` from inside the
/// dialog would close whichever route happens to be on top by then, which
/// need not be this page.
Future<void> showNoMoreCardsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        context.loc.flashcardNoMoreCardsToLearnTitle,
        key: const Key('no_more_cards_dialog_title'),
      ),
      content: Text(context.loc.flashcardNoMoreCardsToLearnDescription),
      actions: [
        TextButton(
          key: const Key('no_more_cards_ok_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.loc.commonOk),
        ),
      ],
    ),
  );
}
