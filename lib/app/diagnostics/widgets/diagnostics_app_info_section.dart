import 'dart:io';

import 'package:discere/app/diagnostics/diagnostics_formatting.dart';
import 'package:discere/app/diagnostics/diagnostics_page_data.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_section_widgets.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/util/byte_format.dart';
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
            'schema ${status.installedSchemaVersion ?? '-'}/${status.supportedSchemaVersion}',
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
        ],
      ),
    );
  }
}
