import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Shown when opening a deck for review whose enrichment state is
/// [DeckEnrichmentState.hidden] — no base or iNaturalist data was ever
/// downloaded for it (the "keine Daten herunterladen" import choice, or a
/// deck imported before that choice existed). Checking for individual
/// no-photo species (`showNoPhotoGapsDialog`) would be pointless here since
/// literally none of them have anything — offer to start the download
/// instead. Returns whether the user wants to start it now.
Future<bool> showNoDataDownloadedDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      key: const Key('no_data_downloaded_dialog'),
      icon: const Icon(Icons.cloud_off_outlined, size: 32),
      title: Text(context.loc.noDataDownloadedDialogTitle),
      content: Text(context.loc.noDataDownloadedDialogMessage),
      actions: [
        TextButton(
          key: const Key('no_data_downloaded_later_button'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.loc.noPhotoGapsDialogSkipButton),
        ),
        FilledButton(
          key: const Key('no_data_downloaded_download_button'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.loc.editDeckDownloadDataButton),
        ),
      ],
    ),
  );
  return result ?? false;
}
