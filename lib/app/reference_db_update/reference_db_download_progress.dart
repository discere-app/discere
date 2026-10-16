import 'package:discere/app/util/byte_format.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/persistence/reference_db_update_state.dart';
import 'package:flutter/material.dart';

/// How far a running reference-DB download is: "40 of 90 MB" over a bar,
/// shown by the notice below every route and by the settings entry.
///
/// Indeterminate until the first bytes arrive, and again once all of them
/// have: unpacking and checking the file takes a while longer.
class ReferenceDbDownloadProgress extends StatelessWidget {
  final ReferenceDbUpdateDownloading download;

  const ReferenceDbDownloadProgress({required this.download, super.key});

  @override
  Widget build(BuildContext context) {
    final progress = download.progress;
    final size = download.update.compressedSizeBytes;
    final receiving = progress != null && progress < 1;
    final text = switch (progress) {
      null => context.loc.referenceDbUpdateDownloadStarting,
      >= 1 => context.loc.referenceDbUpdatePreparing,
      final progress => context.loc.referenceDbUpdateDownloadProgress(
        wholeMegabytes((size * progress).floor()),
        wholeMegabytes(size),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          key: const Key('reference_db_download_progress_bar'),
          value: receiving ? progress : null,
        ),
      ],
    );
  }
}
