import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/theme/ocean_theme/ocean_theme.dart';
import 'package:flutter/material.dart';

/// Shown when the user declines the reference-DB download confirmation
/// ("Nicht jetzt") — a neutral "come back when ready" screen, not an error.
class ReferenceDbDownloadDeclinedShell extends StatelessWidget {
  final VoidCallback onRetry;

  const ReferenceDbDownloadDeclinedShell({required this.onRetry, super.key});

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
                    Text(
                      loc.referenceDbDownloadDeclinedTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      loc.referenceDbDownloadDeclinedMessage,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: onRetry,
                      child: Text(loc.commonRetry),
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
