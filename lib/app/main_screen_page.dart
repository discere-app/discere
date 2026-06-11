import 'dart:async';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/external/inaturalist_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:discere/app/settings_page.dart';
import 'package:discere/app/species_detail_loader_page.dart';
import 'package:discere/catalog/watchlist/watchlist_page.dart';
import 'package:discere/application/species_media/species_media_service.dart';
import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:provider/provider.dart';

import '../../theme/app_spacing.dart';
import 'package:discere/catalog/repository/search_repository.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import '../../learning/service/decks_service.dart';
import '../../enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/catalog/search/search_species_delegate.dart';
import 'package:discere/learning/favorites/favorites_page.dart';
import 'package:discere/learning/decks/home_page.dart';
import 'package:discere/learning/decks/create_deck_page.dart';
import 'package:discere/learning/import/import_deck_page.dart';

class MainScreenPage extends StatefulWidget {
  const MainScreenPage({super.key});

  @override
  State<MainScreenPage> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreenPage> {
  late final DecksService decksService;
  late final LanguageService languageService;
  StreamSubscription<String?>? _notificationSubscription;
  var selectedIndex = 0;
  bool _fabExpanded = false;

  final GlobalKey _deckFavKey = GlobalKey();
  final GlobalKey _deckEditKey = GlobalKey();
  final GlobalKey _deckShareKey = GlobalKey();
  final GlobalKey _searchKey = GlobalKey();
  final GlobalKey _favKey = GlobalKey();
  final GlobalKey _watchlistKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    decksService = Provider.of<DecksService>(context, listen: false);
    languageService = Provider.of<LanguageService>(context, listen: false);

    // Listen for notification taps
    final notificationService = Provider.of<NotificationService>(
      context,
      listen: false,
    );
    _notificationSubscription = notificationService
        .selectNotificationStream
        .stream
        .listen((payload) {
          if (payload == AppConstants.notificationPayloadDailyReview) {
            setState(() {
              selectedIndex = 0; // Route to Home
            });
          }
        });

    decksService.addListener(_onDecksChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkAndShowWelcomeDialog();
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) await _checkAndShowTutorial();
    });
  }

  Future<void> _checkAndShowWelcomeDialog() async {
    final prefs = Provider.of<UserPreferencesService>(context, listen: false);
    if (prefs.hasSeenWelcomeDialog) return;

    final decks = await decksService.getAllDecks();
    if (!mounted) return;

    if (decks.isEmpty) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(context.loc.welcomeTitle),
          content: Text(context.loc.welcomeMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.loc.welcomeSkipAction),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ImportDeckPage(),
                  ),
                );
              },
              child: Text(context.loc.welcomeImportAction),
            ),
          ],
        ),
      );
    }
    prefs.hasSeenWelcomeDialog = true;
  }

  void _onDecksChanged() async {
    final prefs = Provider.of<UserPreferencesService>(context, listen: false);
    if (prefs.hasSeenTutorial || !mounted) return;
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) await _checkAndShowTutorial();
  }

  Future<void> _checkAndShowTutorial() async {
    final prefs = Provider.of<UserPreferencesService>(context, listen: false);
    if (prefs.hasSeenTutorial || !mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final decks = await decksService.getAllDecks();
    if (decks.isEmpty || !mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    prefs.hasSeenTutorial = true;
    _showTutorial();
  }

  void _showTutorial() {
    final loc = context.loc;

    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: 'deckFav',
          keyTarget: _deckFavKey,
          shape: ShapeLightFocus.Circle,
          paddingFocus: 4,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              child: _buildCoachMarkContent(
                loc.tutorialDeckFavTitle,
                loc.tutorialDeckFavDescription,
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'deckEdit',
          keyTarget: _deckEditKey,
          shape: ShapeLightFocus.Circle,
          paddingFocus: 4,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              child: _buildCoachMarkContent(
                loc.tutorialDeckEditTitle,
                loc.tutorialDeckEditDescription,
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'deckShare',
          keyTarget: _deckShareKey,
          shape: ShapeLightFocus.Circle,
          paddingFocus: 4,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              child: _buildCoachMarkContent(
                loc.tutorialDeckShareTitle,
                loc.tutorialDeckShareDescription,
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'search',
          keyTarget: _searchKey,
          shape: ShapeLightFocus.Circle,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              child: _buildCoachMarkContent(
                loc.tutorialSearchTitle,
                loc.tutorialSearchDescription,
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'fav',
          keyTarget: _favKey,
          shape: ShapeLightFocus.Circle,
          paddingFocus: 16,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              child: _buildCoachMarkContent(
                loc.tutorialFavTitle,
                loc.tutorialFavDescription,
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'watchlist',
          keyTarget: _watchlistKey,
          shape: ShapeLightFocus.Circle,
          paddingFocus: 16,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              child: _buildCoachMarkContent(
                loc.tutorialWatchlistTitle,
                loc.tutorialWatchlistDescription,
              ),
            ),
          ],
        ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.85,
      paddingFocus: 8,
      textSkip: loc.tutorialSkip,
      onSkip: () => true,
    ).show(context: context);
  }

  Widget _buildCoachMarkContent(String title, String body) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    decksService.removeListener(_onDecksChanged);
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget page;
    switch (selectedIndex) {
      case 0:
        page = HomePage(
          buildSpeciesDetailPage: _buildSpeciesDetailPage,
          firstCardFavoriteKey: _deckFavKey,
          firstCardEditKey: _deckEditKey,
          firstCardShareKey: _deckShareKey,
        );
        break;
      case 1:
        page = FavoritesPage(buildSpeciesDetailPage: _buildSpeciesDetailPage);
        break;
      case 2:
        page = WatchlistPage(
          resolveSpecies: Provider.of<SpeciesMediaService>(
            context,
            listen: false,
          ).resolveAllWithDownload,
          buildSpeciesDetailPage: _buildSpeciesDetailPage,
        );
        break;
      default:
        throw UnimplementedError('no widget for $selectedIndex');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Discere'),
            actions: [
              IconButton(
                key: _searchKey,
                icon: const Icon(Icons.search),
                onPressed: () {
                  showSearch(
                    context: context,
                    delegate: SearchSpeciesDelegate(
                      Provider.of<SearchRepository>(context, listen: false),
                      languageService,
                      Provider.of<SearchRepository>(
                        context,
                        listen: false,
                      ).searchOnline,
                      Provider.of<INaturalistService>(
                        context,
                        listen: false,
                      ).fetchThumbnailUrl,
                      _buildSpeciesDetailPage,
                    ),
                  );
                },
              ),
              IconButton(
                onPressed: _openSettingsPage,
                icon: const Icon(Icons.settings),
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            items: [
              BottomNavigationBarItem(
                icon: Icon(
                  selectedIndex == 0 ? Icons.home : Icons.home_outlined,
                  key: const ValueKey('nav-home'),
                ),
                label: context.loc.navigationHome,
              ),
              BottomNavigationBarItem(
                icon: KeyedSubtree(
                  key: _favKey,
                  child: Icon(
                    selectedIndex == 1 ? Icons.favorite : Icons.favorite_border,
                    key: const ValueKey('nav-favourites'),
                  ),
                ),
                label: context.loc.navigationFavourites,
              ),
              BottomNavigationBarItem(
                icon: KeyedSubtree(
                  key: _watchlistKey,
                  child: Icon(
                    selectedIndex == 2
                        ? Icons.format_list_bulleted
                        : Icons.format_list_bulleted_outlined,
                    key: const ValueKey('nav-watchlist'),
                  ),
                ),
                label: context.loc.navigationWatchlist,
              ),
            ],
            currentIndex: selectedIndex,
            onTap: (value) {
              setState(() {
                selectedIndex = value;
              });
            },
          ),
          body: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Selector<INatEnrichmentQueueService, INatEnrichmentStatus>(
                      selector: (_, service) => service.status,
                      builder: (context, status, child) {
                        if (!status.hasPendingWork) {
                          return const SizedBox.shrink();
                        }
                        // Once all active decks have at least one image the
                        // deck cards communicate the remaining background work
                        // directly — the global banner is redundant then.
                        if (!status.hasActiveHostCooldown &&
                            status.readyDeckCount >= status.activeDeckCount) {
                          return const SizedBox.shrink();
                        }
                        return _buildEnrichmentBanner(context, status);
                      },
                    ),
                    Expanded(child: page),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: _showAddNewDeckButton(selectedIndex)
              ? _buildFab(context)
              : null,
        );
      },
    );
  }

  Widget _buildSpeciesDetailPage(String speciesId, [Language? language]) {
    return SpeciesDetailLoaderPage(
      speciesId: speciesId,
      language: language,
      buildSpeciesDetailPage: (id) => _buildSpeciesDetailPage(id),
    );
  }

  Widget _buildFab(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_fabExpanded) ..._buildFabOptions(context),
        FloatingActionButton(
          key: const ValueKey('main-fab'),
          heroTag: 'main-fab',
          onPressed: () => setState(() => _fabExpanded = !_fabExpanded),
          child: AnimatedRotation(
            turns: _fabExpanded ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildFabOptions(BuildContext context) {
    return [
      _FabOption(
        icon: Icons.create_new_folder_outlined,
        label: context.loc.createDeckTitle,
        heroTag: 'fab-create',
        onPressed: () async {
          setState(() => _fabExpanded = false);
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateDeckPage()),
          );
          if (mounted) {
            setState(() {});
            await Future.delayed(const Duration(milliseconds: 600));
            if (mounted) await _checkAndShowTutorial();
          }
        },
      ),
      AppSpacing.heightS12,
      _FabOption(
        icon: Icons.download_for_offline_outlined,
        label: context.loc.importDeckTitle,
        heroTag: 'fab-import',
        onPressed: () async {
          setState(() => _fabExpanded = false);
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ImportDeckPage()),
          );
          if (mounted) {
            setState(() {});
            await Future.delayed(const Duration(milliseconds: 600));
            if (mounted) await _checkAndShowTutorial();
          }
        },
      ),
      AppSpacing.heightS12,
    ];
  }

  bool _showAddNewDeckButton(int index) {
    return index == 0 || index == 1;
  }

  Widget _buildEnrichmentBanner(
    BuildContext context,
    INatEnrichmentStatus status,
  ) {
    final theme = Theme.of(context);
    final loc = context.loc;
    final label = status.hasActiveHostCooldown
        ? loc.inatBackgroundBannerSourceCooldown
        : status.hasActiveWork
        ? loc.inatBackgroundBannerPreparing
        : loc.inatBackgroundBannerRetryScheduled;

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_sync_outlined,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }

  void _openSettingsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
  }
}

class _FabOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String heroTag;
  final VoidCallback onPressed;

  const _FabOption({
    required this.icon,
    required this.label,
    required this.heroTag,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s4,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        AppSpacing.widthS12,
        FloatingActionButton.small(
          heroTag: heroTag,
          onPressed: onPressed,
          child: Icon(icon),
        ),
      ],
    );
  }
}
