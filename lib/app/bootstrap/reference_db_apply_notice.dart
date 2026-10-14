import 'package:discere/app/bootstrap/app_restart.dart';
import 'package:discere/app/bootstrap/popup_route_observer.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Wraps the whole app — `FlashcardApp` hands it the navigator through
/// `MaterialApp.builder` — and docks a notice below it while a downloaded
/// reference-database update is staged: "Apply" restarts the app
/// ([AppRestart]), "Later" puts the notice aside until the next start, which
/// installs the update anyway.
///
/// Above the navigator rather than a `MaterialBanner` through the
/// `ScaffoldMessenger`: the notice has to stay visible on every route,
/// including a review session and pages without a `Scaffold`, and it must
/// not take part in route transitions. The navigator stays the first child
/// of the same `Column` whether the notice shows or not, so showing it never
/// rebuilds the routes.
///
/// Above the navigator also means above every modal barrier, so "Apply" is
/// disabled while a dialog, sheet or menu is open ([popupRoutes]): what it is
/// doing may be writing to the user database in several steps, and the
/// restart would close the database between them.
class ReferenceDbApplyNotice extends StatelessWidget {
  const ReferenceDbApplyNotice({
    required this.popupRoutes,
    required this.child,
    super.key,
  });

  final PopupRouteObserver popupRoutes;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final provisioner = context.watch<ReferenceDatabaseProvisioner>();
    final visible = provisioner.hasStagedUpdateToApply;
    final loc = context.loc;
    return Column(
      children: [
        Expanded(
          // The notice takes the bottom inset; the app above must not pad
          // for it a second time.
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: visible,
            child: child,
          ),
        ),
        if (visible)
          MaterialBanner(
            key: const Key('reference_db_apply_notice'),
            leading: const Icon(Icons.system_update_alt),
            content: Text(loc.referenceDbUpdateReadyMessage),
            margin: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom,
            ),
            actions: [
              TextButton(
                key: const Key('reference_db_apply_notice_later_button'),
                onPressed: provisioner.dismissStagedUpdateNotice,
                child: Text(loc.referenceDbUpdateReadyLater),
              ),
              ListenableBuilder(
                listenable: popupRoutes,
                builder: (context, _) => FilledButton(
                  key: const Key('reference_db_apply_notice_apply_button'),
                  onPressed: popupRoutes.isPopupOnTop
                      ? null
                      : context.read<AppRestart>().call,
                  child: Text(loc.referenceDbUpdateReadyApply),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
