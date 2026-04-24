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
  return status.isRunning
      ? loc.inatBackgroundBannerTitle
      : loc.inatBackgroundBannerTitleBackground;
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

String formatEnrichmentDetail(
  AppLocalizations loc,
  INatEnrichmentStatus status,
) {
  if (!status.isRunning) {
    return loc.inatBackgroundBannerContinuing;
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
