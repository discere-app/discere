/// The SQL vocabulary of the enrichment work queue: the table names, and the
/// wire values the queries filter on.
///
/// Shared because the queue is read and written from more than one
/// repository — the ownership/consent write path, the claiming and retry
/// bookkeeping, and the read model behind the deck-facing projection all
/// address the same six tables. Keeping the names in one place is what lets
/// those be separate classes without each inventing its own spelling.
library;

import 'package:discere/enrichment/model/enrichment_work_state.dart';

class EnrichmentWorkTables {
  const EnrichmentWorkTables._();

  static const speciesWork = 'enrichment_species_work';
  static const taxonomyWork = 'enrichment_taxonomy_work';
  static const taxonomyWorkSpecies = 'enrichment_taxonomy_work_species';
  static const capabilityState = 'enrichment_species_capability_state';
  static const deckMembership = 'enrichment_species_deck_membership';
  static const unresolvedNames = 'enrichment_unresolved_names';
}

/// Wire values for the states these tables store, derived from
/// [EnrichmentWorkState] so the SQL cannot drift from the vocabulary the rest
/// of the slice reads.
final pendingState = EnrichmentWorkState.pending.wireName;
final runningState = EnrichmentWorkState.running.wireName;
final retryScheduledState = EnrichmentWorkState.retryScheduled.wireName;
final doneState = EnrichmentWorkState.done.wireName;
final noResultState = EnrichmentWorkState.noResult.wireName;
final permanentFailureState = EnrichmentWorkState.permanentFailure.wireName;

/// Every terminal state: work that will not be attempted again without an
/// explicit reset.
final terminalStates = [
  for (final state in EnrichmentWorkState.values)
    if (state.isTerminal) state.wireName,
];

/// The terminal states that carry a real answer from the source, as opposed
/// to giving up. A stale-image refresh reclaims these but leaves
/// `permanentFailure` alone — that one already exhausted its retry budget,
/// and re-running it would just spend the budget again.
final resolvedStates = [doneState, noResultState];

/// Renders wire values as a SQL literal list. Safe to interpolate: every
/// value originates in [EnrichmentWorkState]/`EnrichmentCapability`, never in
/// user input.
String sqlList(List<String> wireValues) =>
    wireValues.map((value) => "'$value'").join(', ');
