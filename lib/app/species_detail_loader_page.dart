import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/species_detail/species_detail_page.dart';
import 'package:discere/catalog/species_detail/species_detail_tutorial.dart';
import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/enrichment/service/species_media_service.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SpeciesDetailLoaderPage extends StatefulWidget {
  final String speciesId;
  final Language? language;
  final Widget Function(String speciesId)? buildSpeciesDetailPage;
  final Future<bool> Function(
    BuildContext context,
    Set<String> speciesIds,
    Set<String> speciesNames,
  )?
  onAddToDeck;

  const SpeciesDetailLoaderPage({
    super.key,
    required this.speciesId,
    this.language,
    this.buildSpeciesDetailPage,
    this.onAddToDeck,
  });

  @override
  State<SpeciesDetailLoaderPage> createState() =>
      _SpeciesDetailLoaderPageState();
}

class _SpeciesDetailLoaderPageState extends State<SpeciesDetailLoaderPage> {
  late final SpeciesMediaService _speciesMediaService;
  late final INatEnrichmentQueueService _enrichmentQueueService;
  late final DecksService _decksService;
  late Future<SpeciesWithLocalImages?> _futureSpecies;
  List<BaseDeck> _decks = [];
  Map<String, DeckEnrichmentInfo> _lastEnrichmentInfoByDeckId = {};
  bool _isRefreshingImages = false;
  final GlobalKey _addToDeckButtonKey = GlobalKey();
  bool _hasScheduledTutorial = false;

  @override
  void initState() {
    super.initState();
    _speciesMediaService = Provider.of<SpeciesMediaService>(
      context,
      listen: false,
    );
    _enrichmentQueueService = Provider.of<INatEnrichmentQueueService>(
      context,
      listen: false,
    );
    _decksService = Provider.of<DecksService>(context, listen: false);
    _enrichmentQueueService.addListener(_handleEnrichmentQueueChanged);
    _futureSpecies = _speciesMediaService.resolveFromCache(widget.speciesId);
    _loadDecks();
    _refreshINatImagesIfNeeded();
  }

  @override
  void dispose() {
    _enrichmentQueueService.removeListener(_handleEnrichmentQueueChanged);
    super.dispose();
  }

  Future<void> _loadDecks() async {
    final decks = await _decksService.getDecksForSpecies(widget.speciesId);
    if (!mounted) return;
    setState(() {
      _decks = decks;
      _lastEnrichmentInfoByDeckId = {
        for (final deck in decks)
          if (deck.id != null)
            deck.id!: _enrichmentQueueService.deckInfo(deck.id!),
      };
    });
  }

  Future<bool> _handleAddToDeck(
    BuildContext context,
    Set<String> speciesIds,
    Set<String> speciesNames,
  ) async {
    final onAddToDeck = widget.onAddToDeck;
    if (onAddToDeck == null) return false;
    final added = await onAddToDeck(context, speciesIds, speciesNames);
    await _loadDecks();
    return added;
  }

  void _maybeScheduleTutorial() {
    if (_hasScheduledTutorial || widget.onAddToDeck == null) return;
    final prefs = Provider.of<UserPreferencesService>(context, listen: false);
    if (prefs.hasSeenSpeciesDetailTutorial) return;
    _hasScheduledTutorial = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
      prefs.hasSeenSpeciesDetailTutorial = true;
      SpeciesDetailTutorial(addToDeckKey: _addToDeckButtonKey).show(context);
    });
  }

  Future<void> _refreshINatImagesIfNeeded() async {
    final hasCacheEntry = await _speciesMediaService.hasEnrichedPhotos(
      widget.speciesId,
    );
    if (!mounted || hasCacheEntry) return;

    setState(() {
      _isRefreshingImages = true;
    });

    final enriched = await _speciesMediaService.resolveWithFetch(
      widget.speciesId,
    );
    if (!mounted) return;

    setState(() {
      _isRefreshingImages = false;
      if (enriched != null) {
        _futureSpecies = Future.value(enriched);
      }
    });
  }

  void _handleEnrichmentQueueChanged() {
    if (!mounted || _decks.isEmpty) return;

    var shouldRefresh = false;
    final nextInfoByDeckId = <String, DeckEnrichmentInfo>{};

    for (final deck in _decks) {
      final deckId = deck.id;
      if (deckId == null) continue;

      final nextInfo = _enrichmentQueueService.deckInfo(deckId);
      nextInfoByDeckId[deckId] = nextInfo;

      final lastInfo = _lastEnrichmentInfoByDeckId[deckId];
      if (lastInfo == null) continue;

      final hasNewCompletion =
          nextInfo.lastCompletedAt != null &&
          nextInfo.lastCompletedAt != lastInfo.lastCompletedAt;
      if (!nextInfo.isActive && (hasNewCompletion || lastInfo.isActive)) {
        shouldRefresh = true;
      }
    }

    _lastEnrichmentInfoByDeckId = nextInfoByDeckId;

    if (!shouldRefresh) return;
    setState(() {
      _futureSpecies = _speciesMediaService.resolveFromCache(widget.speciesId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SpeciesWithLocalImages?>(
      future: _futureSpecies,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(context.loc.speciesDetailTitle)),
            body: Center(
              child: Text('${context.loc.error}: ${snapshot.error}'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: Text(context.loc.speciesDetailTitle)),
            body: Center(child: Text(context.loc.commonNoData)),
          );
        }

        _maybeScheduleTutorial();
        return SpeciesDetailPage(
          species: snapshot.data!,
          deckNames: _decks.map((d) => d.name).toList(),
          isRefreshingImages: _isRefreshingImages,
          language: widget.language,
          buildSpeciesDetailPage: widget.buildSpeciesDetailPage,
          onAddToDeck: widget.onAddToDeck != null ? _handleAddToDeck : null,
          addToDeckButtonKey: _addToDeckButtonKey,
        );
      },
    );
  }
}
