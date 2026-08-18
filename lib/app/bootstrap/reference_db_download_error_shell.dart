import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/theme/ocean_theme/ocean_theme.dart';
import 'package:flutter/material.dart';

/// Shown when downloading/installing the reference database itself fails
/// (network error, checksum mismatch, unsupported schema, ...).
class ReferenceDbDownloadErrorShell extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const ReferenceDbDownloadErrorShell({
    required this.error,
    required this.onRetry,
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
                    Text(
                      loc.referenceDbDownloadErrorTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(loc.describeError(error), textAlign: TextAlign.center),
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
