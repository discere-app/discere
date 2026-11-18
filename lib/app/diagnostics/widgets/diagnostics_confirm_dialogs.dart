/// The destructive diagnostics actions confirm first. They are blunt on
/// purpose — closing all outstanding work, deleting the images of species
/// no longer needed on a restart, clearing every preference — so none
/// should be one stray tap away.
library;

import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:material_ui/material_ui.dart';

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

Future<bool> showImageStorageSweepConfirmation(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.loc.diagnosticsImageStorageSweepConfirmTitle),
      content: Text(dialogContext.loc.diagnosticsImageStorageSweepConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(dialogContext.loc.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(dialogContext.loc.diagnosticsImageStorageSweepRestart),
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
