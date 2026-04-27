import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/enrichment_progress_status.dart';

String? formatEnrichmentPhaseLabel(
  AppLocalizations loc,
  INatEnrichmentPhase? phase,
) {
  return switch (phase) {
    INatEnrichmentPhase.nameResolution => loc.inatBackgroundPhaseNameResolution,
    INatEnrichmentPhase.cover => loc.inatBackgroundPhaseCover,
    INatEnrichmentPhase.base => loc.inatBackgroundPhaseBase,
    INatEnrichmentPhase.names => loc.inatBackgroundPhaseNames,
    INatEnrichmentPhase.inat => loc.inatBackgroundPhaseINat,
    INatEnrichmentPhase.idle || null => null,
  };
}

String formatEnrichmentTitle(
  AppLocalizations loc,
  INatEnrichmentStatus status,
) {
  return status.preferBackgroundMessaging
      ? loc.inatBackgroundBannerTitleBackground
      : loc.inatBackgroundBannerTitle;
}

String formatEnrichmentDetail(
  AppLocalizations loc,
  INatEnrichmentStatus status, {
  String? localeTag,
  DateTime? now,
}) {
  if (status.hasActiveHostCooldown) {
    return loc.inatBackgroundBannerSourceCooldown;
  }

  if (status.preferBackgroundMessaging) {
    return loc.inatBackgroundBannerContinuing;
  }

  if (!status.isRunning && status.nextAttemptAt != null) {
    return loc.inatBackgroundBannerRetryFromINat(
      _formatApproxRetryTime(
        status.nextAttemptAt!,
        localeTag: localeTag,
        now: now,
      ),
    );
  }

  final phaseLabel =
      formatEnrichmentPhaseLabel(loc, status.phase) ?? loc.inatDeckStatusActive;

  if (status.total <= 0) {
    return phaseLabel;
  }

  return loc.inatBackgroundBannerProgress(
    phaseLabel,
    status.completed,
    status.total,
  );
}

String formatEnrichmentReadySummary(
  AppLocalizations loc,
  INatEnrichmentStatus status,
) {
  return loc.inatBackgroundBannerReady(
    status.readyDeckCount,
    status.totalDeckCount,
  );
}

String formatDeckPendingStatusLabel(
  AppLocalizations loc, {
  required bool hasActiveHostCooldown,
  required bool isQuickPassReady,
  DateTime? nextAttemptAt,
  String? localeTag,
  DateTime? now,
  required INatEnrichmentPhase? phase,
  required String fallback,
}) {
  if (hasActiveHostCooldown) {
    return loc.inatDeckStatusWaitingForSource;
  }
  if (nextAttemptAt != null) {
    final formatted = _formatApproxRetryTime(
      nextAttemptAt,
      localeTag: localeTag,
      now: now,
    );
    if (isQuickPassReady) {
      return loc.inatDeckStatusReadyRetryFromINat(formatted);
    }
    return loc.inatDeckStatusRetryFromINat(formatted);
  }
  if (isQuickPassReady) {
    return loc.inatDeckStatusReadyContinuing;
  }
  return formatEnrichmentPhaseLabel(loc, phase) ?? fallback;
}

String _formatApproxRetryTime(
  DateTime nextAttemptAt, {
  String? localeTag,
  DateTime? now,
}) {
  final effectiveNow = (now ?? DateTime.now()).toLocal();
  final localAttemptAt = nextAttemptAt.toLocal();
  final normalizedLocale = localeTag?.toLowerCase() ?? 'en';
  final isSameDay =
      effectiveNow.year == localAttemptAt.year &&
      effectiveNow.month == localAttemptAt.month &&
      effectiveNow.day == localAttemptAt.day;
  final isTomorrow =
      effectiveNow
          .copyWith(
            hour: 0,
            minute: 0,
            second: 0,
            millisecond: 0,
            microsecond: 0,
          )
          .add(const Duration(days: 1)) ==
      localAttemptAt.copyWith(
        hour: 0,
        minute: 0,
        second: 0,
        millisecond: 0,
        microsecond: 0,
      );
  final time = _formatHourMinute(localAttemptAt);
  if (isSameDay) {
    return time;
  }
  if (isTomorrow) {
    return normalizedLocale.startsWith('de')
        ? 'morgen um $time'
        : 'tomorrow at $time';
  }
  final date = _formatDate(localAttemptAt, normalizedLocale);
  return '$date $time';
}

String _formatHourMinute(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatDate(DateTime dateTime, String localeTag) {
  if (localeTag.startsWith('de')) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    return '$day.$month.';
  }
  return '${dateTime.year.toString().padLeft(4, '0')}-'
      '${dateTime.month.toString().padLeft(2, '0')}-'
      '${dateTime.day.toString().padLeft(2, '0')}';
}
