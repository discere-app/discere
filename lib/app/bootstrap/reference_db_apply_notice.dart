import 'package:discere/app/bootstrap/app_restart.dart';
import 'package:discere/app/reference_db_update/reference_db_download_progress.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/persistence/reference_db_update_service.dart';
import 'package:discere/shared/persistence/reference_db_update_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Wraps the whole app — `FlashcardApp` hands it the navigator through
/// `MaterialApp.builder` — and docks a notice below it while a
/// reference-database update is on its way: its download progress, a failed
/// download with "Try again", and once it is staged "Apply", which restarts
/// the app ([AppRestart]), and "Later", which puts the notice aside until
/// the next start installs the update anyway.
///
/// Above the navigator rather than a `MaterialBanner` through the
/// `ScaffoldMessenger`: the notice has to stay visible on every route,
/// including a review session and pages without a `Scaffold`, and it must
/// not take part in route transitions. The navigator stays the first child
/// of the same `Column` whether the notice shows or not, so showing it never
/// rebuilds the routes.
class ReferenceDbApplyNotice extends StatelessWidget {
  const ReferenceDbApplyNotice({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<ReferenceDbUpdateService>();
    final notice = _notice(context, updates);
    return Column(
      children: [
        Expanded(
          // The notice takes the bottom inset; the app above must not pad
          // for it a second time.
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: notice != null,
            child: child,
          ),
        ),
        ?notice,
      ],
    );
  }

  Widget? _notice(BuildContext context, ReferenceDbUpdateService updates) {
    final loc = context.loc;
    final margin = EdgeInsets.only(
      bottom: MediaQuery.paddingOf(context).bottom,
    );
    switch (updates.state) {
      case final ReferenceDbUpdateDownloading download:
        // No actions: a MaterialBanner needs one, and there is nothing to
        // do but wait.
        return Material(
          key: const Key('reference_db_download_notice'),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12).add(margin),
            child: Row(
              children: [
                const Icon(Icons.cloud_download_outlined),
                const SizedBox(width: 16),
                Expanded(
                  child: ReferenceDbDownloadProgress(download: download),
                ),
              ],
            ),
          ),
        );
      case ReferenceDbUpdateDownloadFailed(:final error):
        return MaterialBanner(
          key: const Key('reference_db_download_failed_notice'),
          leading: const Icon(Icons.error_outline),
          content: Text(
            loc.referenceDbUpdateDownloadFailed(loc.describeError(error)),
          ),
          margin: margin,
          actions: [
            TextButton(
              key: const Key('reference_db_download_failed_later_button'),
              onPressed: updates.dismissDownloadFailure,
              child: Text(loc.referenceDbUpdateReadyLater),
            ),
            FilledButton(
              key: const Key('reference_db_download_retry_button'),
              onPressed: updates.download,
              child: Text(loc.referenceDbUpdateRetry),
            ),
          ],
        );
      case ReferenceDbUpdateStaged(noticeDismissed: false):
        return MaterialBanner(
          key: const Key('reference_db_apply_notice'),
          leading: const Icon(Icons.system_update_alt),
          content: Text(loc.referenceDbUpdateReadyMessage),
          margin: margin,
          actions: [
            TextButton(
              key: const Key('reference_db_apply_notice_later_button'),
              onPressed: updates.dismissStagedNotice,
              child: Text(loc.referenceDbUpdateReadyLater),
            ),
            FilledButton(
              key: const Key('reference_db_apply_notice_apply_button'),
              onPressed: context.read<AppRestart>().call,
              child: Text(loc.referenceDbUpdateReadyApply),
            ),
          ],
        );
      default:
        return null;
    }
  }
}
