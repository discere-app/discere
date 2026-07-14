import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Shows a confirmation dialog for optional iNaturalist enrichment.
///
/// Reference images are always downloaded automatically; this dialog only
/// asks whether the user also wants iNaturalist photos and common names.
Future<bool> showINatDownloadDialog(
  BuildContext context,
  List<String> deckIds,
) async {
  if (deckIds.isEmpty) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('inat_download_dialog'),
      icon: const Icon(Icons.photo_library_outlined, size: 32),
      title: Text(ctx.loc.inatDialogTitle),
      content: SingleChildScrollView(child: Text(ctx.loc.inatDialogMessage)),
      actions: [
        TextButton(
          key: const Key('inat_skip_button'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(ctx.loc.inatDialogCancel),
        ),
        FilledButton.icon(
          key: const Key('inat_download_button'),
          onPressed: () => Navigator.of(ctx).pop(true),
          icon: const Icon(Icons.download, size: 18),
          label: Text(ctx.loc.inatDialogConfirm),
        ),
      ],
    ),
  );
  return confirmed == true;
}
