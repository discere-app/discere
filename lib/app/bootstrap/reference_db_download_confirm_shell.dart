import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/util/byte_format.dart';
import 'package:discere/theme/ocean_theme/ocean_theme.dart';
import 'package:flutter/material.dart';

/// Asks the user to confirm the (multi-hundred-MB) reference-DB download
/// before it starts — always shown, on Wi-Fi or cellular; the cellular
/// warning line only appears when [onWifi] is false.
class ReferenceDbDownloadConfirmShell extends StatelessWidget {
  final int sizeBytes;
  final bool onWifi;
  final VoidCallback onDownloadNow;
  final VoidCallback onNotNow;

  const ReferenceDbDownloadConfirmShell({
    required this.sizeBytes,
    required this.onWifi,
    required this.onDownloadNow,
    required this.onNotNow,
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
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      onWifi
                          ? Icons.cloud_download_outlined
                          : Icons.signal_cellular_alt,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      loc.referenceDbDownloadConfirmTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      loc.referenceDbDownloadConfirmMessage(
                        formatApproxSizeMB(sizeBytes),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (!onWifi) ...[
                      const SizedBox(height: 8),
                      Text(
                        loc.referenceDbDownloadConfirmCellularWarning,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: onDownloadNow,
                      child: Text(loc.referenceDbDownloadConfirmDownloadNow),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: onNotNow,
                      child: Text(loc.referenceDbDownloadConfirmNotNow),
                    ),
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
