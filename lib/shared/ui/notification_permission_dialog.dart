import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Soft, in-app ask shown before the OS notification-permission prompt,
/// so declining doesn't burn the platform's one-shot system dialog.
///
/// Covers both daily review reminders and deck-enrichment progress —
/// both are gated by the same OS-level notification permission, so there
/// is only one ask, regardless of which feature triggered it.
Future<bool> showNotificationPermissionDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('notification_permission_dialog'),
      icon: const Icon(Icons.notifications_active_outlined, size: 32),
      title: Text(ctx.loc.notificationPermissionDialogTitle),
      content: SingleChildScrollView(
        child: Text(ctx.loc.notificationPermissionDialogMessage),
      ),
      actions: [
        TextButton(
          key: const Key('notification_permission_skip_button'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(ctx.loc.notificationPermissionDialogCancel),
        ),
        FilledButton.icon(
          key: const Key('notification_permission_confirm_button'),
          onPressed: () => Navigator.of(ctx).pop(true),
          icon: const Icon(Icons.notifications_outlined, size: 18),
          label: Text(ctx.loc.notificationPermissionDialogConfirm),
        ),
      ],
    ),
  );
  return confirmed == true;
}
