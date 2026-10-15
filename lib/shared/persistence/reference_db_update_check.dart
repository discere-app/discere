/// What this session knows about a newer reference database, for the
/// diagnostics page.
///
/// Kept apart from `ReferenceDatabaseProvisioner.pendingUpdate`, which is
/// what the update dialog offers and is cleared when the user declines it:
/// declining puts the offer away, not the knowledge that a newer version
/// exists.
sealed class ReferenceDbUpdateCheck {
  const ReferenceDbUpdateCheck();
}

/// The background check of the manifest has not finished yet.
final class ReferenceDbUpdateCheckRunning extends ReferenceDbUpdateCheck {
  const ReferenceDbUpdateCheckRunning();
}

/// The check failed (offline, server unreachable, a manifest this build
/// cannot use); the reason is in the log.
final class ReferenceDbUpdateCheckFailed extends ReferenceDbUpdateCheck {
  const ReferenceDbUpdateCheckFailed();
}

/// The installed version is the newest the manifest offers.
final class ReferenceDbUpToDate extends ReferenceDbUpdateCheck {
  const ReferenceDbUpToDate();
}

/// The manifest offers [version], newer than the installed one.
final class ReferenceDbNewerVersionFound extends ReferenceDbUpdateCheck {
  final int version;

  /// The user turned the offer down for this session.
  final bool declined;

  const ReferenceDbNewerVersionFound(this.version, {this.declined = false});
}
