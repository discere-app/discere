import 'dart:io';

import 'package:discere/app/diagnostics/diagnostics_formatting.dart';
import 'package:discere/app/diagnostics/diagnostics_page_data.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_section_widgets.dart';
import 'package:discere/app/util/byte_format.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/persistence/reference_db_update_state.dart';
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
            subtitle: Text(_referenceDbSubtitle(context)),
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

  String _referenceDbSubtitle(BuildContext context) {
    final status = data.referenceDbStatus;
    if (!status.fileExists) {
      return context.loc.diagnosticsReferenceDbNotInstalled;
    }
    final version = status.installedVersion;
    // The file keeps the time it was written by the download: a staged
    // update is renamed into place, which leaves that time as it is.
    final downloadedAt = status.fileModifiedAt;
    final schema = status.installedSchemaVersion;
    return [
      [
        if (version != null) context.loc.diagnosticsReferenceDbVersion(version),
        if (downloadedAt != null)
          context.loc.diagnosticsReferenceDbDownloadedOn(
            formatDiagnosticsDate(context, downloadedAt),
          ),
        if (status.fileSizeBytes != null) formatBytes(status.fileSizeBytes!),
      ].join(' · '),
      if (data.referenceDbSources.isNotEmpty)
        context.loc.diagnosticsReferenceDbDataSources(
          data.referenceDbSources
              .map((source) => '${source.name} ${source.version}')
              .join(', '),
        ),
      if (schema != null) context.loc.diagnosticsReferenceDbSchema(schema),
    ].join('\n');
  }

  String _updateSubtitle(BuildContext context) {
    final loc = context.loc;
    return switch (data.referenceDbUpdateState) {
      ReferenceDbUpdateNotChecked() =>
        loc.diagnosticsReferenceDbUpdateNotChecked,
      ReferenceDbUpdateChecking() =>
        loc.diagnosticsReferenceDbUpdateCheckRunning,
      ReferenceDbUpdateCheckFailed() =>
        loc.diagnosticsReferenceDbUpdateCheckFailed,
      ReferenceDbUpToDate() => loc.diagnosticsReferenceDbUpToDate,
      ReferenceDbUpdateAvailable(:final update, declined: false) =>
        loc.diagnosticsReferenceDbUpdateAvailable(update.version),
      ReferenceDbUpdateAvailable(:final update, declined: true) =>
        loc.diagnosticsReferenceDbUpdateDeclined(update.version),
      ReferenceDbUpdateDownloading(:final update, :final progress) =>
        loc.diagnosticsReferenceDbUpdateDownloading(
          update.version,
          ((progress ?? 0) * 100).floor(),
        ),
      ReferenceDbUpdateDownloadFailed(:final update) =>
        loc.diagnosticsReferenceDbUpdateDownloadFailed(update.version),
      ReferenceDbUpdateStaged(:final version) =>
        loc.diagnosticsReferenceDbUpdateStaged(version),
    };
  }

  String _referenceIdsSubtitle(BuildContext context) {
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
    // Which version the learning progress matches only needs saying when
    // the last run does not already say it: after a failure, or with no run
    // on record — then it stands alone, since "not run yet" would be wrong.
    final applied = data.referenceIdsAppliedVersion;
    if (applied == null) return runLine;
    final appliedLine = context.loc.diagnosticsReferenceIdsAppliedVersion(
      applied,
    );
    return switch (run) {
      null => appliedLine,
      ReferenceIdMigrationSucceeded(:final referenceDbVersion)
          when referenceDbVersion == applied =>
        runLine,
      _ => '$runLine\n$appliedLine',
    };
  }
}
