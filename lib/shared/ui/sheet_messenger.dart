import 'package:flutter/material.dart';

/// Gives a modal bottom sheet its own SnackBars.
///
/// The app's messenger shows a SnackBar on the page underneath, which the
/// sheet covers — so a message meant for the sheet, such as why a write
/// failed while it stays open to try again, goes through [messengerKey]
/// instead and shows at the sheet's own bottom edge.
class SheetMessenger extends StatelessWidget {
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final Widget child;

  const SheetMessenger({
    required this.messengerKey,
    required this.child,
    super.key,
  });

  /// Shows [message] in the sheet keyed by [messengerKey].
  static void show(
    GlobalKey<ScaffoldMessengerState> messengerKey,
    String message,
  ) {
    messengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: messengerKey,
      child: Scaffold(backgroundColor: Colors.transparent, body: child),
    );
  }
}
