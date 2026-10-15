import 'dart:async';

import 'package:discere/app/bootstrap/app_restart.dart';
import 'package:discere/app/reference_db_update/reference_db_update_dialog.dart';
import 'package:discere/app/util/byte_format.dart';
import 'package:discere/catalog/model/source.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_db_update_service.dart';
import 'package:discere/shared/persistence/reference_db_update_state.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/shared/util/failure_logging.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The installed species database — version and data releases — and its
/// update, by hand: checking for one and downloading one found (also after
/// the start dialog was declined).
///
/// It reads the same [ReferenceDbUpdateService] state as
/// `ReferenceDbApplyNotice` below every route, and offers an action exactly
/// when the notice does not: while the notice shows a download's progress,
/// its failure with "Try again", or a staged update with "Apply", this
/// section only says which state the update is in. Once that notice is put
/// aside, applying the staged update moves back here, since otherwise only
/// restarting the app would install it.
class SettingsReferenceDbSection extends StatefulWidget {
  const SettingsReferenceDbSection({super.key});

  @override
  State<SettingsReferenceDbSection> createState() =>
      _SettingsReferenceDbSectionState();
}

class _SettingsReferenceDbSectionState
    extends State<SettingsReferenceDbSection> {
  static final _log = Logger.forType(SettingsReferenceDbSection);

  /// Loaded once: the watched update state rebuilds this on every
  /// percentage point of a download. Sources that cannot be read cost their
  /// line, not the settings page.
  late final Future<(int?, List<Source>)> _installed = (
    ReferenceDatabaseProvisioner.currentVersion(),
    context
        .read<SourceService>()
        .getVersionedSources()
        .warnOnFailure(_log, 'Reference DB sources load')
        .catchError((Object _) => const <Source>[]),
  ).wait;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updates = context.watch<ReferenceDbUpdateService>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.loc.settingsReferenceDbTitle,
          style: theme.textTheme.titleSmall,
        ),
        AppSpacing.heightS8,
        SectionCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InstalledLine(installed: _installed),
                AppSpacing.heightS16,
                ..._updateRows(context, updates),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _updateRows(
    BuildContext context,
    ReferenceDbUpdateService updates,
  ) {
    final loc = context.loc;
    Widget action(String key, String label, VoidCallback onPressed) => Align(
      alignment: Alignment.centerRight,
      child: FilledButton.tonal(
        key: Key(key),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
    final checkNow = action(
      'settings_reference_db_check_button',
      loc.settingsReferenceDbCheckNow,
      () => unawaited(updates.checkNow()),
    );
    return switch (updates.state) {
      ReferenceDbUpdateNotChecked() => [
        Text(loc.settingsReferenceDbNotChecked),
        checkNow,
      ],
      ReferenceDbUpdateChecking() => [
        Text(loc.settingsReferenceDbChecking),
        AppSpacing.heightS8,
        const LinearProgressIndicator(),
      ],
      ReferenceDbUpdateCheckFailed(:final error) => [
        Text(loc.settingsReferenceDbCheckFailed(loc.describeError(error))),
        checkNow,
      ],
      ReferenceDbUpToDate() => [
        Text(loc.settingsReferenceDbUpToDate),
        checkNow,
      ],
      ReferenceDbUpdateAvailable(:final update) => [
        Text(
          loc.settingsReferenceDbAvailable(
            update.version,
            formatApproxSizeMB(update.compressedSizeBytes),
          ),
        ),
        action(
          'settings_reference_db_download_button',
          loc.settingsReferenceDbDownload,
          () => unawaited(confirmReferenceDbUpdate(context, updates, update)),
        ),
      ],
      ReferenceDbUpdateDownloading(:final update) => [
        Text(loc.settingsReferenceDbDownloading(update.version)),
      ],
      ReferenceDbUpdateDownloadFailed(:final error) => [
        Text(loc.referenceDbUpdateDownloadFailed(loc.describeError(error))),
      ],
      ReferenceDbUpdateStaged(:final version, noticeDismissed: false) => [
        Text(loc.settingsReferenceDbStagedInNotice(version)),
      ],
      ReferenceDbUpdateStaged(:final version, noticeDismissed: true) => [
        Text(loc.settingsReferenceDbStaged(version)),
        action(
          'settings_reference_db_apply_button',
          loc.referenceDbUpdateReadyApply,
          context.read<AppRestart>().call,
        ),
      ],
    };
  }
}

/// "Version 2" over "Data: FishBase v26.07, SeaLifeBase v26.04", each left
/// out while unknown.
class _InstalledLine extends StatelessWidget {
  final Future<(int?, List<Source>)> installed;

  const _InstalledLine({required this.installed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<(int?, List<Source>)>(
      future: installed,
      builder: (context, snapshot) {
        final (version, releases) = snapshot.data ?? (null, const <Source>[]);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (version != null)
              Text(
                context.loc.settingsReferenceDbVersion(version),
                style: theme.textTheme.titleMedium,
              ),
            if (releases.isNotEmpty)
              Text(
                context.loc.settingsReferenceDbDataSources(
                  releases
                      .map((source) => '${source.name} ${source.version}')
                      .join(', '),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        );
      },
    );
  }
}
