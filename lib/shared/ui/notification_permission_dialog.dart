import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Runs the complete notification soft-ask flow in one place: checks whether
/// the in-app prompt is still needed, shows [showNotificationPermissionDialog]
/// and forwards the user's choice to the OS permission request (or records
/// the decline). No-op when the prompt is not needed.
///
/// The user's dialog answer is always forwarded to [NotificationService],
/// even if [context] got unmounted while the dialog was open — the service
/// calls don't need a context and dropping the answer would re-prompt later.
/// Callers that continue with UI work afterwards must re-check `mounted`
/// themselves.
Future<void> ensureNotificationPermission(BuildContext context) async {
  final notificationService = Provider.of<NotificationService>(
    context,
    listen: false,
  );
  if (!await notificationService.shouldPromptForPermission()) return;
  if (!context.mounted) return;
  final shouldRequest = await showNotificationPermissionDialog(context);
  if (shouldRequest) {
    await notificationService.requestPermissions();
  } else {
    await notificationService.declinePermissionPrompt();
  }
}

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
