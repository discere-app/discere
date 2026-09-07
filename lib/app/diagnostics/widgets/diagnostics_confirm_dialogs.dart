/// The two destructive diagnostics actions confirm first. Both are blunt on
/// purpose — closing all outstanding work and clearing every preference —
/// so neither should be one stray tap away.
library;

import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

Future<bool> showCloseAllEnrichmentConfirmation(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.loc.diagnosticsCloseAllEnrichmentConfirmTitle),
      content: Text(dialogContext.loc.diagnosticsCloseAllEnrichmentConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(dialogContext.loc.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(dialogContext.loc.diagnosticsCloseAllEnrichment),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

Future<bool> showResetAllSettingsConfirmation(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.loc.diagnosticsResetAllSettingsConfirmTitle),
      content: Text(dialogContext.loc.diagnosticsResetAllSettingsConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(dialogContext.loc.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(dialogContext.loc.diagnosticsResetAllSettings),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
