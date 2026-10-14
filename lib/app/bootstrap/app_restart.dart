import 'package:discere/app/bootstrap/app_session.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:flutter/widgets.dart';

/// Restarts the app from inside: the running session ends, the databases
/// close and the bootstrap runs again exactly as on a cold start — which is
/// where a staged reference database is installed and its aliases applied.
/// The app comes back on the home screen with every service built anew.
///
/// Provided above the app by `BootstrapApp`, for the notice that offers to
/// apply a staged reference-database update.
class AppRestart {
  const AppRestart(this._restart);

  final VoidCallback _restart;

  void call() => _restart();
}

/// Ends [session] and closes the databases, then runs [bootstrap] again.
///
/// Called as the bootstrap swaps the app for its loading screen. The first
/// step waits for that frame: it disposes the session's provider tree and
/// every open route, so nothing new can start from the UI, and what a page
/// does on leaving (a review session hands its notification rescheduling
/// off) has been issued. What is still running is then waited for, not cut
/// off:
/// - the write sequences counted in [AppSession.userDataWrites] — saving a
///   deck, an import, a review — so none is cut between two of its steps;
/// - [AppSession.stop], for the background work;
/// - an empty write transaction, for every statement already handed to the
///   user database. Closing without it would roll back a transaction still
///   running and fail the statements queued behind it.
Future<T> restartApp<T>(
  AppSession session,
  Future<T> Function() bootstrap,
) async {
  await WidgetsBinding.instance.endOfFrame;
  await session.userDataWrites.drained();
  await session.stop();
  final userDb = await DatabaseHelper.userDb;
  await userDb.transaction((_) async {});
  await DatabaseHelper.close();
  return bootstrap();
}
