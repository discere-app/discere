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
import 'package:provider/provider.dart';

import '../../theme/app_spacing.dart';
import 'package:discere/catalog/repository/search_repository.dart';
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowWelcomeDialog();
    });
  }

  Future<void> _checkAndShowWelcomeDialog() async {
    final prefs = Provider.of<UserPreferencesService>(context, listen: false);
    if (!prefs.hasSeenWelcomeDialog) {
      final decks = await decksService.getAllDecks();
      if (decks.isEmpty && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(context.loc.welcomeTitle),
            content: Text(context.loc.welcomeMessage),
            actions: [
              TextButton(
                onPressed: () {
                  prefs.hasSeenWelcomeDialog = true;
                  Navigator.pop(context);
                },
                child: Text(context.loc.welcomeSkipAction),
              ),
              ElevatedButton(
                onPressed: () {
                  prefs.hasSeenWelcomeDialog = true;
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
      } else {
        // If user already has decks, mark as seen so it doesn't show up later if decks are deleted
        prefs.hasSeenWelcomeDialog = true;
      }
    }
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget page;
    switch (selectedIndex) {
      case 0:
        page = const HomePage();
        break;
      case 1:
        page = const FavoritesPage();
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
                icon: Icon(
                  selectedIndex == 1 ? Icons.favorite : Icons.favorite_border,
                  key: const ValueKey('nav-favourites'),
                ),
                label: context.loc.navigationFavourites,
              ),
              BottomNavigationBarItem(
                icon: Icon(
                  selectedIndex == 2
                      ? Icons.format_list_bulleted
                      : Icons.format_list_bulleted_outlined,
                  key: const ValueKey('nav-watchlist'),
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
                        if (!status.isRunning) {
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

  Widget _buildSpeciesDetailPage(String speciesId) {
    return SpeciesDetailLoaderPage(speciesId: speciesId);
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
          if (mounted) setState(() {});
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
          if (mounted) setState(() {});
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
    final progressValue = status.total > 0
        ? status.completed / status.total
        : null;

    String phaseLabel;
    switch (status.phase) {
      case INatEnrichmentPhase.base:
        phaseLabel = loc.inatBackgroundPhaseBase;
        break;
      case INatEnrichmentPhase.names:
        phaseLabel = loc.inatBackgroundPhaseNames;
        break;
      case INatEnrichmentPhase.inat:
        phaseLabel = loc.inatBackgroundPhaseINat;
        break;
      case INatEnrichmentPhase.idle:
        phaseLabel = loc.inatBackgroundPhaseINat;
        break;
    }

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_sync_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          loc.inatBackgroundBannerTitle,
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          loc.inatBackgroundBannerProgress(
                            phaseLabel,
                            status.completed,
                            status.total,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            LinearProgressIndicator(value: progressValue, minHeight: 2),
          ],
        ),
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
