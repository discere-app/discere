import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/util/byte_format.dart';
import 'package:discere/theme/ocean_theme/ocean_theme.dart';
import 'package:flutter/material.dart';

/// Shown while the reference database is actively downloading, after the
/// user has confirmed via `ReferenceDbDownloadConfirmShell`.
class ReferenceDbDownloadShell extends StatelessWidget {
  final double progress;
  final int? sizeBytes;

  const ReferenceDbDownloadShell({
    required this.progress,
    this.sizeBytes,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: oceanTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final loc = AppLocalizations.of(context)!;
          final percent = (progress.clamp(0, 1) * 100).round();
          final sizeText = sizeBytes;
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: progress.clamp(0, 1)),
                    const SizedBox(height: 16),
                    Text(
                      loc.referenceDbDownloadStatus(percent),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (sizeText != null && sizeText > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        loc.referenceDbDownloadSizeInfo(
                          formatApproxSizeMB(sizeText),
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
