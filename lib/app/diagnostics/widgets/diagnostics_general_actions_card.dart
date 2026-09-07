import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Actions that are not about enrichment or logs: forcing a deck-catalog
/// check, and wiping every stored preference.
class DiagnosticsGeneralActionsCard extends StatelessWidget {
  final bool isCheckingDeckUpdates;
  final VoidCallback onCheckDeckUpdates;
  final VoidCallback onResetAllSettings;

  const DiagnosticsGeneralActionsCard({
    required this.isCheckingDeckUpdates,
    required this.onCheckDeckUpdates,
    required this.onResetAllSettings,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: isCheckingDeckUpdates
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync_outlined),
            title: Text(context.loc.diagnosticsCheckDeckUpdatesNow),
            onTap: isCheckingDeckUpdates ? null : onCheckDeckUpdates,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: Text(context.loc.diagnosticsResetAllSettings),
            onTap: onResetAllSettings,
          ),
        ],
      ),
    );
  }
}
