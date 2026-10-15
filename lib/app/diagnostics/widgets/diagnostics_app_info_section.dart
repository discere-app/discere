import 'dart:io';

import 'package:discere/app/diagnostics/diagnostics_formatting.dart';
import 'package:discere/app/diagnostics/diagnostics_page_data.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_section_widgets.dart';
import 'package:discere/app/util/byte_format.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration_run.dart';
import 'package:flutter/material.dart';

/// App version, platform and reference-DB status as one section — all static
/// facts about this install rather than actionable diagnostics, so they share
/// a card and sit last.
class DiagnosticsAppInfoSection extends StatelessWidget {
  final DiagnosticsPageData data;

  const DiagnosticsAppInfoSection({required this.data, super.key});

  @override
  Widget build(BuildContext context) {
    final status = data.referenceDbStatus;
    final referenceDbSubtitle = !status.fileExists
        ? context.loc.diagnosticsReferenceDbNotInstalled
        : [
            'v${status.installedVersion ?? '-'}',
            'schema ${status.installedSchemaVersion ?? '-'}/${status.supportedSchemaVersions.join(',')}',
            if (status.fileSizeBytes != null)
              formatBytes(status.fileSizeBytes!),
            if (status.fileModifiedAt != null)
              formatDiagnosticsDateTime(
                context,
                status.fileModifiedAt!,
              ).replaceAll('\n', ' '),
          ].join(' • ');
    return Card(
      child: Column(
        children: [
          DiagnosticsSectionHeader(
            title: context.loc.diagnosticsAppInfoTitle,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${data.packageInfo.appName} ${data.packageInfo.version} '
                  '(${data.packageInfo.buildNumber})',
                ),
                Text(
                  '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: Text(context.loc.diagnosticsReferenceDbTitle),
            subtitle: Text(referenceDbSubtitle),
          ),
          ListTile(
            title: Text(context.loc.diagnosticsReferenceDbUpdateTitle),
            subtitle: Text(_updateSubtitle(context)),
          ),
          ListTile(
            title: Text(context.loc.diagnosticsReferenceIdsTitle),
            subtitle: Text(_referenceIdsSubtitle(context)),
          ),
        ],
      ),
    );
  }

  String _updateSubtitle(BuildContext context) {
    final available = data.availableReferenceDbVersion;
    final staged = data.stagedReferenceDbVersion;
    if (available == null && staged == null) {
      return context.loc.diagnosticsReferenceDbUpdateNone;
    }
    return [
      if (available != null)
        context.loc.diagnosticsReferenceDbUpdateAvailable(available),
      if (staged != null)
        context.loc.diagnosticsReferenceDbUpdateStaged(staged),
    ].join('\n');
  }

  String _referenceIdsSubtitle(BuildContext context) {
    final applied = data.referenceIdsAppliedVersion;
    final appliedLine = applied == null
        ? context.loc.diagnosticsReferenceIdsNeverApplied
        : context.loc.diagnosticsReferenceIdsAppliedVersion(applied);
    final run = data.lastReferenceIdMigrationRun;
    final time = run == null
        ? ''
        : formatDiagnosticsDateTime(context, run.ranAt).replaceAll('\n', ' ');
    final runLine = switch (run) {
      null => context.loc.diagnosticsReferenceIdsLastRunNone,
      ReferenceIdMigrationSucceeded() =>
        context.loc.diagnosticsReferenceIdsLastRunSucceeded(
          time,
          run.referenceDbVersion,
          run.totalRewritten,
          run.totalDropped,
          run.referencedIdCount,
          run.aliasCount,
        ),
      ReferenceIdMigrationFailed() =>
        context.loc.diagnosticsReferenceIdsLastRunFailed(
          time,
          run.referenceDbVersion,
        ),
    };
    return '$appliedLine\n$runLine';
  }
}
