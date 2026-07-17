import 'package:discere/enrichment/model/deck_enrichment_state.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/theme/ocean_theme/ocean_colors.dart';
import 'package:flutter/material.dart';

/// Icon, color, label, and description per [DeckEnrichmentState] — the
/// single place that decides how each enrichment state looks, shared by the
/// deck-card hint and the state-explanation dialog. Follows the same
/// pattern as `LearningModeStyle` in the learning slice.
class EnrichmentStateStyle {
  const EnrichmentStateStyle();

  IconData iconFor(DeckEnrichmentState state) {
    switch (state) {
      case DeckEnrichmentState.hidden:
        return Icons.check_circle_outline;
      case DeckEnrichmentState.pending:
        return Icons.hourglass_top_outlined;
      case DeckEnrichmentState.loadingBase:
        return Icons.cloud_download_outlined;
      case DeckEnrichmentState.loadingExtended:
        return Icons.cloud_sync_outlined;
      case DeckEnrichmentState.done:
        return Icons.check_circle;
      case DeckEnrichmentState.doneWithGaps:
        return Icons.check_circle_outline;
      case DeckEnrichmentState.cooldown:
        return Icons.cloud_off_outlined;
      case DeckEnrichmentState.paused:
        return Icons.pause_circle_outline;
      case DeckEnrichmentState.failed:
        return Icons.error_outline;
    }
  }

  Color colorFor(DeckEnrichmentState state) {
    switch (state) {
      case DeckEnrichmentState.hidden:
      case DeckEnrichmentState.pending:
      case DeckEnrichmentState.cooldown:
      case DeckEnrichmentState.paused:
        return OceanColors.primaryTextDark;
      case DeckEnrichmentState.loadingBase:
        return OceanColors.primaryBlue;
      case DeckEnrichmentState.loadingExtended:
      case DeckEnrichmentState.done:
      case DeckEnrichmentState.doneWithGaps:
        return OceanColors.success;
      case DeckEnrichmentState.failed:
        return OceanColors.error;
    }
  }

  String labelFor(DeckEnrichmentState state, AppLocalizations loc) {
    switch (state) {
      case DeckEnrichmentState.hidden:
      case DeckEnrichmentState.pending:
        return loc.inatDeckStatePending;
      case DeckEnrichmentState.loadingBase:
        return loc.inatDeckStateLoadingBase;
      case DeckEnrichmentState.loadingExtended:
        return loc.inatDeckStateLoadingExtended;
      case DeckEnrichmentState.done:
        return loc.inatDeckStateDone;
      case DeckEnrichmentState.doneWithGaps:
        return loc.inatDeckStateDoneWithGaps;
      case DeckEnrichmentState.cooldown:
        return loc.inatDeckStateCooldown;
      case DeckEnrichmentState.paused:
        return loc.inatDeckStatePaused;
      case DeckEnrichmentState.failed:
        return loc.inatDeckStateFailed;
    }
  }

  String descriptionFor(DeckEnrichmentState state, AppLocalizations loc) {
    switch (state) {
      case DeckEnrichmentState.hidden:
      case DeckEnrichmentState.pending:
        return loc.inatDeckStateDescPending;
      case DeckEnrichmentState.loadingBase:
        return loc.inatDeckStateDescLoadingBase;
      case DeckEnrichmentState.loadingExtended:
        return loc.inatDeckStateDescLoadingExtended;
      case DeckEnrichmentState.done:
        return loc.inatDeckStateDescDone;
      case DeckEnrichmentState.doneWithGaps:
        return loc.inatDeckStateDescDoneWithGaps;
      case DeckEnrichmentState.cooldown:
        return loc.inatDeckStateDescCooldown;
      case DeckEnrichmentState.paused:
        return loc.inatDeckStateDescPaused;
      case DeckEnrichmentState.failed:
        return loc.inatDeckStateDescFailed;
    }
  }
}
