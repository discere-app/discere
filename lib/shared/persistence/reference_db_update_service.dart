import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_db_update_state.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';

/// The one place that knows where this session stands with a newer
/// reference database ([state]) and moves it along: the check at start, a
/// check the user asks for, declining, downloading and staging, putting the
/// notice aside. The update dialog, the notice below every route, the
/// settings entry and the diagnostics page read it; the file work itself is
/// [ReferenceDatabaseProvisioner]'s.
///
/// Lives as long as the bootstrap, across in-app restarts: each bootstrap
/// installs what was staged and calls [checkAtStart], which starts the
/// session's state anew.
class ReferenceDbUpdateService extends ChangeNotifier {
  static final _log = Logger.forType(ReferenceDbUpdateService);

  ReferenceDbUpdateService({
    required ReferenceDatabaseProvisioner provisioner,
    required NetworkAvailability networkAvailability,
  }) : _provisioner = provisioner,
       _networkAvailability = networkAvailability;

  final ReferenceDatabaseProvisioner _provisioner;
  final NetworkAvailability _networkAvailability;

  ReferenceDbUpdateState _state = const ReferenceDbUpdateNotChecked();

  /// Whether the newest check is the one the bootstrap started. Only that
  /// one offers its result through the start dialog ([startOffer]); one the
  /// user asked for in the settings shows its result there.
  bool _checkedAtStart = false;

  ReferenceDbUpdateState get state => _state;

  /// The update the start dialog offers, once per session: found by the
  /// check at start and neither declined nor taken up yet.
  ReferenceDbUpdateInfo? get startOffer => switch (_state) {
    ReferenceDbUpdateAvailable(:final update, declined: false)
        when _checkedAtStart =>
      update,
    _ => null,
  };

  /// For the dialog's cellular-data warning, asked when it is about to show
  /// rather than when the update was found.
  Future<bool> isOnWifi() => _networkAvailability.isOnWifi();

  /// The bootstrap's check, run unawaited on its fast path. Never throws: a
  /// failed check must not take away the copy already in use.
  Future<void> checkAtStart() {
    _checkedAtStart = true;
    return _check();
  }

  /// A check the user asked for. Only when no check is running and nothing
  /// is found, downloading or staged — there is nothing to look for then.
  Future<void> checkNow() async {
    if (_state
        case ReferenceDbUpdateNotChecked() ||
            ReferenceDbUpToDate() ||
            ReferenceDbUpdateCheckFailed()) {
      _checkedAtStart = false;
      await _check();
    }
  }

  Future<void> _check() async {
    _setState(const ReferenceDbUpdateChecking());
    try {
      final update = await _provisioner.findNewerVersion();
      _setState(
        update == null
            ? const ReferenceDbUpToDate()
            : ReferenceDbUpdateAvailable(update),
      );
    } catch (error) {
      _log.warn(
        'Reference database update check failed, keeping cached copy: '
        '$error',
      );
      _setState(ReferenceDbUpdateCheckFailed(error));
    }
  }

  /// Turns the found update down for this session.
  void decline() {
    if (_state case ReferenceDbUpdateAvailable(:final update)) {
      _setState(ReferenceDbUpdateAvailable(update, declined: true));
    }
  }

  /// Downloads and stages the found update — also one declined before, and
  /// again after a failed attempt. A no-op while a download runs, so a
  /// second tap or a second place starting one never runs it twice. Never
  /// throws: a failure becomes [ReferenceDbUpdateDownloadFailed].
  Future<void> download() async {
    final update = switch (_state) {
      ReferenceDbUpdateAvailable(:final update) => update,
      ReferenceDbUpdateDownloadFailed(:final update) => update,
      _ => null,
    };
    if (update == null) return;
    _setState(ReferenceDbUpdateDownloading(update));
    try {
      await _provisioner.stage(
        update,
        onProgress: (progress) => _reportProgress(update, progress),
      );
      _setState(ReferenceDbUpdateStaged(update.version));
    } catch (error, stackTrace) {
      _log.warn(
        'Reference database update download failed',
        error: error,
        stackTrace: stackTrace,
      );
      _setState(ReferenceDbUpdateDownloadFailed(update, error));
    }
  }

  /// Passes progress on per percentage point: the downloader reports every
  /// chunk, and each report rebuilds whatever shows it.
  void _reportProgress(ReferenceDbUpdateInfo update, double progress) {
    final previous = switch (_state) {
      ReferenceDbUpdateDownloading(:final progress) => progress,
      _ => null,
    };
    if (previous != null &&
        (previous * 100).floor() == (progress * 100).floor()) {
      return;
    }
    _setState(ReferenceDbUpdateDownloading(update, progress: progress));
  }

  /// Closes the notice of a failed download. The update stays available,
  /// as declined, so the settings still offer it.
  void dismissDownloadFailure() {
    if (_state case ReferenceDbUpdateDownloadFailed(:final update)) {
      _setState(ReferenceDbUpdateAvailable(update, declined: true));
    }
  }

  /// Puts the notice for the staged update aside for this session. The
  /// update stays staged and is installed on the next start.
  void dismissStagedNotice() {
    if (_state case ReferenceDbUpdateStaged(
      :final version,
      noticeDismissed: false,
    )) {
      _setState(ReferenceDbUpdateStaged(version, noticeDismissed: true));
    }
  }

  void _setState(ReferenceDbUpdateState state) {
    _state = state;
    notifyListeners();
  }
}
