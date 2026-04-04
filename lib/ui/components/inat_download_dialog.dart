import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../service/learning/decks_service.dart';

/// Shows a confirmation dialog asking the user if they want to download
/// additional images from iNaturalist, and if confirmed, shows a progress
/// dialog while fetching.
///
/// Returns a download summary, or an empty summary if skipped/failed.
Future<ImageDownloadSummary> showINatDownloadFlow(
  BuildContext context,
  dynamic deckIdOrIds,
) async {
  final List<String> deckIds = deckIdOrIds is String
      ? [deckIdOrIds]
      : (deckIdOrIds as List).cast<String>();
  if (deckIds.isEmpty) return ImageDownloadSummary.empty;

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

  if (confirmed != true) {
    if (context.mounted) {
      // Still trigger base image download in the background so the decks are functional
      final decksService = Provider.of<DecksService>(context, listen: false);
      decksService
          .downloadBaseImagesForDecks(deckIds)
          .catchError((_) => ImageDownloadSummary.empty);
    }
    return ImageDownloadSummary.empty;
  }

  if (!context.mounted) return ImageDownloadSummary.empty;

  // Show progress dialog.
  var result = ImageDownloadSummary.empty;
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _INatProgressDialog(
      deckIds: deckIds,
      onDone: (summary) {
        result = summary;
      },
    ),
  );

  return result;
}

class _INatProgressDialog extends StatefulWidget {
  final List<String> deckIds;
  final void Function(ImageDownloadSummary summary) onDone;

  const _INatProgressDialog({required this.deckIds, required this.onDone});

  @override
  State<_INatProgressDialog> createState() => _INatProgressDialogState();
}

class _INatProgressDialogState extends State<_INatProgressDialog> {
  int _completed = 0;
  int _total = 0;
  bool _isDone = false;
  var _summary = ImageDownloadSummary.empty;
  String _phase = 'base'; // 'base' or 'inat'

  @override
  void initState() {
    super.initState();
    _startFetch();
  }

  Future<void> _startFetch() async {
    final decksService = Provider.of<DecksService>(context, listen: false);

    // Step 1: Base Images (Reference)
    var totalSummary = ImageDownloadSummary.empty;
    try {
      totalSummary += await decksService.downloadBaseImagesForDecks(
        widget.deckIds,
        onProgress: (completed, total) {
          if (mounted) {
            setState(() {
              _completed = completed;
              _total = total;
            });
          }
        },
      );
    } catch (e) {
      debugPrint('Base image download failed in dialog: $e');
    }

    if (!mounted) return;

    // Step 2: iNat
    setState(() {
      _phase = 'inat';
    });

    totalSummary += await decksService.fetchINatPhotosForDecks(
      widget.deckIds,
      onProgress: (completed, total) {
        if (mounted) {
          setState(() {
            _completed = completed;
            _total = total;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isDone = true;
        _summary = totalSummary;
      });
      widget.onDone(totalSummary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;

    return AlertDialog(
      key: const Key('inat_progress_dialog'),
      title: Text(_isDone ? '✓' : loc.inatProgressTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isDone) ...[
            LinearProgressIndicator(
              value: _total > 0 ? _completed / _total : null,
            ),
            const SizedBox(height: 16),
            Text(loc.inatProgressMessage(_completed, _total)),
            const SizedBox(height: 4),
            Text(
              _phase == 'base'
                  ? loc.inatProgressPhaseBase
                  : loc.inatProgressPhaseINat,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ] else ...[
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 16),
            Text(
              loc.inatDoneMessage(_summary.imageCount, _summary.speciesCount),
            ),
          ],
        ],
      ),
      actions: _isDone
          ? [
              FilledButton(
                key: const Key('inat_done_button'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(loc.commonOk),
              ),
            ]
          : null,
    );
  }
}
