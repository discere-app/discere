import 'dart:ui';

import 'package:discere/enrichment/queue/model/inat_enrichment_status.dart';
import 'package:discere/enrichment/queue/presentation/enrichment_status_presenter.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/service/foreground_service_keeper.dart';
import 'package:discere/shared/service/network_availability.dart';

/// Decides whether the app keeps a visible background presence for
/// enrichment — on Android, a foreground service with its notification — and
/// what that notification says.
///
/// Only relevant while backgrounded: in the foreground the in-app banner
/// already communicates progress, so a second, separate system notification
/// would be noise. Progress is folded into the keepalive notification the
/// process already needs rather than shown alongside it.
class EnrichmentBackgroundPresence {
  final ForegroundServiceKeeper _keeper;
  final NetworkAvailability _networkAvailability;

  /// False in the instances that only observe state and never run work; they
  /// must not put a notification up for someone else's queue.
  final bool _enabled;

  /// What was last asked of the keeper. Compared before acting so a refresh
  /// that changes nothing does not restart the service.
  bool _wanted = false;

  EnrichmentBackgroundPresence({
    required ForegroundServiceKeeper keeper,
    required NetworkAvailability networkAvailability,
    required bool enabled,
  }) : _keeper = keeper,
       _networkAvailability = networkAvailability,
       _enabled = enabled;

  Future<void> initialize() => _keeper.initialize();

  /// Whether the keepalive service is actually running — surfaced for the
  /// diagnostics page. Always false on non-Android platforms.
  Future<bool> get isRunning => _keeper.isRunning;

  /// Brings the presence in line with [status], and refreshes what the
  /// notification says while it is up.
  Future<void> sync({
    required bool isInForeground,
    required INatEnrichmentStatus status,
  }) async {
    if (!_enabled) return;
    await _setWanted(
      !isInForeground &&
          _isWorthKeepingAlive(status) &&
          _networkAvailability.isOnline,
    );
    // The text follows the presence: writing content for a notification that
    // is not up says nothing to anyone.
    if (!_wanted) return;
    await _updateContent(status);
  }

  /// Puts the presence up without waiting for the next state refresh, for a
  /// deck scheduled while the app is already in the background — the work
  /// starts immediately and the process has to survive it.
  Future<void> ensureStarted() async {
    if (!_enabled) return;
    await _setWanted(true);
  }

  /// Takes the presence down. Not awaited by [dispose] callers, so it must
  /// not be the only thing keeping the service alive.
  Future<void> stop() => _setWanted(false);

  /// Kept up through an active host cooldown as well as active work, so a
  /// short rate limit does not tear the notification down only to bring it
  /// straight back — it switches to the cooldown message instead. That also
  /// keeps the process alive through the cooldown, which is what lets the
  /// queue resume on its own once it clears.
  bool _isWorthKeepingAlive(INatEnrichmentStatus status) =>
      status.hasActiveWork || status.hasActiveHostCooldown;

  Future<void> _setWanted(bool wanted) async {
    if (wanted == _wanted) return;
    _wanted = wanted;
    await (wanted ? _keeper.startKeepingAlive() : _keeper.stopKeepingAlive());
  }

  Future<void> _updateContent(INatEnrichmentStatus status) async {
    final loc = _localizationsForDeviceLocale();
    await _keeper.updateNotificationContent(
      title: status.preferBackgroundMessaging
          ? loc.inatBackgroundBannerTitleBackground
          : loc.inatBackgroundBannerTitle,
      text: formatDeckPendingStatusLabel(
        loc,
        hasActiveHostCooldown: status.hasActiveHostCooldown,
        progressCompleted: status.completed,
        progressTotal: status.total,
      ),
    );
  }

  /// Notifications fire outside the widget tree, so the locale is read from
  /// the platform rather than from a BuildContext.
  AppLocalizations _localizationsForDeviceLocale() {
    final locale = PlatformDispatcher.instance.locale;
    return lookupAppLocalizations(
      locale.languageCode == 'de' ? const Locale('de') : const Locale('en'),
    );
  }
}
