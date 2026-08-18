import 'package:discere/theme/ocean_theme/ocean_theme.dart';
import 'package:flutter/material.dart';

/// Generic loading screen shown while `BootstrapApp` is still assembling
/// services — before there's anything reference-DB-specific to report.
class BootstrapShell extends StatelessWidget {
  final String status;

  const BootstrapShell({required this.status, super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: oceanTheme,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  status,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
