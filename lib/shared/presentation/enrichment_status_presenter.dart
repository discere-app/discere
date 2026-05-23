import 'package:discere/l10n/app_localizations.dart';

String formatDeckPendingStatusLabel(
  AppLocalizations loc, {
  required bool hasActiveHostCooldown,
  required int progressCompleted,
  required int progressTotal,
}) {
  if (hasActiveHostCooldown) return loc.inatDeckStatusCooldown;
  if (progressTotal > 0) {
    return loc.inatDeckStatusLoading(progressCompleted, progressTotal);
  }
  return loc.inatDeckStatusLoadingIndeterminate;
}
