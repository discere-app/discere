abstract class EnrichmentBackgroundScheduler {
  Future<void> initialize();

  Future<void> cancelAllPendingProcessing();

  Future<void> cancelProcessingForDeck(String deckId);
}

class NoopEnrichmentBackgroundScheduler
    implements EnrichmentBackgroundScheduler {
  const NoopEnrichmentBackgroundScheduler();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> cancelAllPendingProcessing() async {}

  @override
  Future<void> cancelProcessingForDeck(String deckId) async {}
}
