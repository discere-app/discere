/// One user-initiated search, and whether it has since been superseded.
///
/// Typing a new character abandons the previous run: its queries stop being
/// scheduled and its isolate response is discarded. Deciding *when* that
/// happens is the caller's business — `SpeciesSearchService` mints a run per
/// search and invalidates it on the next keystroke — while the repository
/// only honours what it is handed. That split is why this is passed in
/// rather than tracked in the repository: a repository that decides which
/// user interaction is still current has grown a second job.
class SearchRun {
  /// Monotonically increasing, so the search isolate can tell a response
  /// that belongs to an older query from the current one (see
  /// `SearchWorkerResponse.isStale`).
  final int generation;

  final bool Function() _isAbandoned;

  const SearchRun({
    required this.generation,
    required bool Function() isAbandoned,
  }) : _isAbandoned = isAbandoned;

  /// A newer search has started; whatever this run still holds is of no
  /// further interest.
  bool get isAbandoned => _isAbandoned();

  /// A run that is never superseded, for callers with no notion of a newer
  /// search — a one-off lookup rather than a typing session.
  static const SearchRun single = SearchRun(
    generation: 0,
    isAbandoned: _never,
  );

  static bool _never() => false;
}
