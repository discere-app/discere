import 'package:discere/shared/persistence/reference_database_provisioner.dart';

/// Where this session stands with a newer reference database — what the
/// update dialog, the notice below every route, the settings entry and the
/// diagnostics page all show. Held by `ReferenceDbUpdateService`; nothing of
/// it is persisted, so every start begins with a fresh check.
sealed class ReferenceDbUpdateState {
  const ReferenceDbUpdateState();
}

/// No check has run this session — the start took the blocking download,
/// which installed the newest version there was.
final class ReferenceDbUpdateNotChecked extends ReferenceDbUpdateState {
  const ReferenceDbUpdateNotChecked();
}

/// The manifest is being fetched.
final class ReferenceDbUpdateChecking extends ReferenceDbUpdateState {
  const ReferenceDbUpdateChecking();
}

/// The check failed (offline, server unreachable, a manifest this build
/// cannot use).
final class ReferenceDbUpdateCheckFailed extends ReferenceDbUpdateState {
  final Object error;

  const ReferenceDbUpdateCheckFailed(this.error);
}

/// The installed version is the newest the manifest offers.
final class ReferenceDbUpToDate extends ReferenceDbUpdateState {
  const ReferenceDbUpToDate();
}

/// The manifest offers [update], newer than the installed version.
final class ReferenceDbUpdateAvailable extends ReferenceDbUpdateState {
  final ReferenceDbUpdateInfo update;

  /// The user turned the offer down for this session. It can still be
  /// downloaded from the settings.
  final bool declined;

  const ReferenceDbUpdateAvailable(this.update, {this.declined = false});
}

/// [update] is being downloaded and staged.
final class ReferenceDbUpdateDownloading extends ReferenceDbUpdateState {
  final ReferenceDbUpdateInfo update;

  /// Share of the download received, 0 to 1; null until the first bytes
  /// arrive. At 1 the file is still being unpacked and checked.
  final double? progress;

  const ReferenceDbUpdateDownloading(this.update, {this.progress});
}

/// Downloading [update] failed; it can be tried again.
final class ReferenceDbUpdateDownloadFailed extends ReferenceDbUpdateState {
  final ReferenceDbUpdateInfo update;
  final Object error;

  const ReferenceDbUpdateDownloadFailed(this.update, this.error);
}

/// [version] is staged and installed by the next bootstrap — a restart
/// through "Apply", or the next start.
final class ReferenceDbUpdateStaged extends ReferenceDbUpdateState {
  final int version;

  /// The user put the notice offering to apply it aside for this session.
  final bool noticeDismissed;

  const ReferenceDbUpdateStaged(this.version, {this.noticeDismissed = false});
}
