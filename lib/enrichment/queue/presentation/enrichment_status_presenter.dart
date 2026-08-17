import 'package:discere/l10n/app_localizations.dart';

// Shown as a percentage rather than "completed / total", matching
// DeckEnrichmentHint on the deck-card overview (deck_enrichment_hint.dart):
// progressTotal sums several independent per-species work stages (image,
// common names, iNat backfill, taxonomy), so it isn't the deck's actual
// species count — "X / Y species" would misstate what Y counts.
String formatDeckPendingStatusLabel(
  AppLocalizations loc, {
  required bool hasActiveHostCooldown,
  required int progressCompleted,
  required int progressTotal,
}) {
  if (hasActiveHostCooldown) return loc.inatDeckStatusCooldown;
  if (progressTotal > 0) {
    final percent = (progressCompleted * 100 / progressTotal).round();
    return loc.inatDeckStatusLoadingPercent(percent);
  }
  return loc.inatDeckStatusLoadingIndeterminate;
}
