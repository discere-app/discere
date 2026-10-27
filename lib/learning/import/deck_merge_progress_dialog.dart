import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Shown while a confirmed merge runs: it can take a while for a large
/// entry, and neither a tap outside nor the back gesture may dismiss it —
/// the merge goes on either way, and the dialog is what says so.
class DeckMergeProgressDialog extends StatelessWidget {
  const DeckMergeProgressDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('deck_merge_progress_dialog'),
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 24),
            Expanded(child: Text(context.loc.deckMergeInProgress)),
          ],
        ),
      ),
    );
  }
}
