import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// The persisted-log switch and the two actions on the log file.
class DiagnosticsLogCard extends StatelessWidget {
  final bool persistErrorLogs;
  final ValueChanged<bool> onPersistChanged;
  final VoidCallback onOpenLog;
  final VoidCallback onClearLog;

  const DiagnosticsLogCard({
    required this.persistErrorLogs,
    required this.onPersistChanged,
    required this.onOpenLog,
    required this.onClearLog,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            value: persistErrorLogs,
            title: Text(context.loc.diagnosticsPersistLogsTitle),
            subtitle: Text(context.loc.diagnosticsPersistLogsSubtitle),
            onChanged: onPersistChanged,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text(context.loc.diagnosticsViewLog),
            onTap: onOpenLog,
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(context.loc.diagnosticsClearLog),
            onTap: onClearLog,
          ),
        ],
      ),
    );
  }
}
