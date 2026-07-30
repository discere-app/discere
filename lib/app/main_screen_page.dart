import 'dart:async';
import 'dart:io' show Platform;

import 'package:discere/app/main_screen_tutorial.dart';
import 'package:discere/app/settings_page.dart';
import 'package:discere/app/species_detail_loader_page.dart';
import 'package:discere/catalog/repository/search_repository.dart';
import 'package:discere/catalog/search/search_species_delegate.dart';
import 'package:discere/catalog/watchlist/watchlist_page.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/learning/decks/add_to_deck/add_to_deck_sheet.dart';
import 'package:discere/learning/decks/create_deck_page.dart';
import 'package:discere/learning/decks/home_page.dart';
import 'package:discere/learning/favorites/favorites_page.dart';
import 'package:discere/learning/import/import_deck_page.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/service/navigation_tab_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/shared/ui/app_bottom_navigation_bar.dart';
import 'package:discere/shared/ui/notification_permission_dialog.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MainScreenPage extends StatefulWidget {
  const MainScreenPage({super.key});

  @override
  State<MainScreenPage> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreenPage> {
  late final DecksService decksService;
  late final LanguageService languageService;
  late final NavigationTabService _navigationTabService;
  StreamSubscription<String?>? _notificationSubscription;
  bool _fabExpanded = false;

  final GlobalKey _deckFavKey = GlobalKey();
  final GlobalKey _watchlistKey = GlobalKey();

  // Tabs are built lazily on first visit, then kept in the tree via
  // IndexedStack so switching tabs preserves scroll position/filters
  // instead of tearing the previous tab's state down.
  final Set<int> _visitedTabIndices = {};

  @override
  void initState() {
    super.initState();
    decksService = Provider.of<DecksService>(context, listen: false);
    languageService = Provider.of<LanguageService>(context, listen: false);
    _navigationTabService = Provider.of<NavigationTabService>(
      context,
      listen: false,
    );

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
            _navigationTabService.selectTab(0);
          }
        });

    decksService.addListener(_onDecksChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkAndShowWelcomeDialog();
      if (mounted) await _checkAndShowNotificationPermissionPrompt();
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) await _checkAndShowTutorial();
    });
  }

  Future<void> _checkAndShowNotificationPermissionPrompt() async {
    final notificationService = Provider.of<NotificationService>(
      context,
      listen: false,
    );
    if (await notificationService.shouldPromptForPermission()) {
      if (!mounted) return;
      await ensureNotificationPermission(context);
      return;
    }
    if (!Platform.isAndroid) {
      await notificationService.requestPermissions();
    }
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
    MainScreenTutorial(
      deckFavKey: _deckFavKey,
      watchlistKey: _watchlistKey,
    ).show(context);
  }

  @override
  void dispose() {
    decksService.removeListener(_onDecksChanged);
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NavigationTabService>(
      builder: (context, navService, _) {
        return _buildScaffold(context, navService.selectedIndex);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, int selectedIndex) {
    _visitedTabIndices.add(selectedIndex);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Scaffold(
          appBar: AppBar(
            title: Text(context.loc.appTitle),
            actions: [
              IconButton(
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
                      _addToDeck,
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
          bottomNavigationBar: AppBottomNavigationBar(
            watchlistKey: _watchlistKey,
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
                    Expanded(
                      child: IndexedStack(
                        index: selectedIndex,
                        children: List.generate(
                          3,
                          (index) => _visitedTabIndices.contains(index)
                              ? _buildTabPage(index)
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
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

  Widget _buildTabPage(int index) {
    switch (index) {
      case 0:
        return HomePage(
          buildSpeciesDetailPage: _buildSpeciesDetailPage,
          firstCardFavoriteKey: _deckFavKey,
        );
      case 1:
        return FavoritesPage(buildSpeciesDetailPage: _buildSpeciesDetailPage);
      case 2:
        return WatchlistPage(
          resolveSpecies: Provider.of<SpeciesMediaService>(
            context,
            listen: false,
          ).resolveAllWithDownload,
          buildSpeciesDetailPage: _buildSpeciesDetailPage,
        );
      default:
        throw UnimplementedError('no widget for $index');
    }
  }

  Widget _buildSpeciesDetailPage(String speciesId, [Language? language]) {
    return SpeciesDetailLoaderPage(
      speciesId: speciesId,
      language: language,
      buildSpeciesDetailPage: (id) => _buildSpeciesDetailPage(id),
      onAddToDeck: _addToDeck,
    );
  }

  Future<bool> _addToDeck(
    BuildContext context,
    Set<String> speciesIds,
    Set<String> speciesNames,
  ) {
    return showAddToDeckSheet(
      context,
      speciesIds: speciesIds,
      speciesNames: speciesNames,
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
          LinearProgressIndicator(
            minHeight: 2,
            value: status.total > 0
                ? (status.completed / status.total).clamp(0.0, 1.0)
                : null,
          ),
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
