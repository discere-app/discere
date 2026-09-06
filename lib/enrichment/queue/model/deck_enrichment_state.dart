/// User-facing state for the per-deck enrichment hint.
///
/// Distilled from the deck's cover job status plus its species/taxonomy
/// `DeckEnrichmentProjection` (host cooldown, retry waits, permanent
/// failures) into a flat list of mutually exclusive states the UI can switch
/// on.
enum DeckEnrichmentState {
  /// No enrichment is active or pending and nothing has ever been attempted.
  /// The UI shows nothing.
  hidden,

  /// Scheduled but nothing has started running yet.
  pending,

  /// Image-loading capabilities (`base`, `inatPrimary`) are still in flight
  /// for at least one species. The deck is not yet learnable.
  loadingBase,

  /// Every species has reached a terminal image outcome, but common names
  /// and/or taxonomy/backfill work is still running (or the deck's cover job
  /// hasn't finished yet). The UI uses the same color as [done] to signal
  /// learnability.
  loadingExtended,

  /// All species/taxonomy work (and the cover job, if any) reached terminal
  /// state and no capability permanently failed.
  done,

  /// All work reached terminal state, but some non-image capability
  /// (common names, taxonomy, backfill, or an unresolved name) permanently
  /// failed. The deck is still fully learnable.
  doneWithGaps,

  /// Active or pending work, but the host cooldown has been in effect for
  /// longer than the display threshold. Overrides [loadingBase] and
  /// [loadingExtended] so the user sees what is blocking progress.
  cooldown,

  /// The soonest retry across the deck's cover job and species/taxonomy work
  /// is further in the future than the pause display threshold. Overrides
  /// [loadingBase] and [loadingExtended].
  paused,

  /// Every species' image capabilities are terminal, no image was ever
  /// obtained for any of them, and at least one image capability
  /// (`base`/`inatPrimary`) permanently failed. Deck is not learnable; user
  /// must re-trigger enrichment from the Edit-Deck page.
  failed,
}
