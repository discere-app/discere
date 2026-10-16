/// Asks whether to download a reference-DB update that became available
/// while the app was running — at start, or from the settings.
library;

import 'dart:async';

import 'package:discere/app/util/byte_format.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_db_update_service.dart';
import 'package:flutter/material.dart';

/// Asks about [update] and acts on the answer: "update now" starts the
/// download in the background, where the notice below every route shows its
/// progress; "not now" declines it for this session.
Future<void> confirmReferenceDbUpdate(
  BuildContext context,
  ReferenceDbUpdateService updates,
  ReferenceDbUpdateInfo update,
) async {
  final onWifi = await updates.isOnWifi();
  if (!context.mounted) return;
  final updateNow = await showReferenceDbUpdateDialog(
    context,
    compressedSizeBytes: update.compressedSizeBytes,
    onWifi: onWifi,
  );
  if (updateNow) {
    unawaited(updates.download());
  } else {
    updates.decline();
  }
}

/// Not dismissible by tapping outside: the download is several hundred
/// megabytes, so both answers should be deliberate. Returns true for "update
/// now".
Future<bool> showReferenceDbUpdateDialog(
  BuildContext context, {
  required int compressedSizeBytes,
  required bool onWifi,
}) async {
  final loc = context.loc;
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        onWifi ? Icons.cloud_download_outlined : Icons.signal_cellular_alt,
      ),
      title: Text(loc.referenceDbUpdateConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.referenceDbUpdateAvailableMessage(
              formatApproxSizeMB(compressedSizeBytes),
            ),
          ),
          if (!onWifi) ...[
            const SizedBox(height: 8),
            Text(
              loc.referenceDbDownloadConfirmCellularWarning,
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(loc.referenceDbDownloadConfirmNotNow),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(loc.referenceDbUpdateConfirmUpdateNow),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
