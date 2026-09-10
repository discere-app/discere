import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Asks whether to start the next batch of new cards, and stays open until
/// that batch actually exists.
///
/// Closing on the tap and initializing afterwards would leave the already
/// answered card on screen until a database write of a whole batch finished —
/// a window long enough to be visible, and long enough for a second tap to
/// start the batch twice.
class ActivateMoreCardsDialog extends StatefulWidget {
  /// Writes the next batch. Awaited before the dialog closes.
  final Future<void> Function() onActivate;

  /// Runs once the batch exists and the dialog is gone.
  final VoidCallback onActivated;

  const ActivateMoreCardsDialog({
    super.key,
    required this.onActivate,
    required this.onActivated,
  });

  @override
  State<ActivateMoreCardsDialog> createState() =>
      _ActivateMoreCardsDialogState();
}

class _ActivateMoreCardsDialogState extends State<ActivateMoreCardsDialog> {
  bool _isActivating = false;

  Future<void> _activate() async {
    if (_isActivating) return;
    setState(() => _isActivating = true);
    // Captured before awaiting, because this dialog need not still be the
    // topmost route once the batch is written: the deck page listens on the
    // enrichment queue and can push a photo-gap dialog over this one at any
    // moment. A plain pop() closes whatever sits on top, which in that case
    // would be the wrong dialog and would leave this one behind with both
    // its buttons disabled.
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    try {
      await widget.onActivate();
    } finally {
      if (mounted) {
        if (route == null || route.isCurrent) {
          navigator.pop();
        } else {
          navigator.removeRoute(route);
        }
      }
    }
    widget.onActivated();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        context.loc.flashcardActivateMoreCardsTitle,
        key: const Key('activation_dialog_title'),
      ),
      content: Text(context.loc.flashcardActivateMoreCardsDescription),
      actions: [
        TextButton(
          key: const Key('activation_dialog_yes_button'),
          onPressed: _isActivating ? null : _activate,
          child: Text(context.loc.commonYes),
        ),
        TextButton(
          onPressed: _isActivating
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(context.loc.commonNo),
        ),
      ],
    );
  }
}
