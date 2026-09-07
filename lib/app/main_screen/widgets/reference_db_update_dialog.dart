/// Asks whether to download a reference-DB update that became available
/// while the app was running.
///
/// Not dismissible by tapping outside: the download is several hundred
/// megabytes, so both answers should be deliberate. Returns true for "update
/// now"; the caller owns what happens next, including dismissing the pending
/// update when the answer is no.
library;

import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/util/byte_format.dart';
import 'package:flutter/material.dart';

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
