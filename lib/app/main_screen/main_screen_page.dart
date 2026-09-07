import 'dart:async';

import 'package:discere/app/main_screen/main_screen_tutorial.dart';
import 'package:discere/app/main_screen/reference_db_base_refresh_prompt.dart';
import 'package:discere/app/main_screen/widgets/main_screen_app_bar.dart';
import 'package:discere/app/main_screen/widgets/main_screen_enrichment_banner.dart';
import 'package:discere/app/main_screen/widgets/main_screen_fab.dart';
import 'package:discere/app/main_screen/widgets/main_screen_tabs.dart';
import 'package:discere/app/main_screen/widgets/reference_db_update_dialog.dart';
import 'package:discere/app/settings/settings_page.dart';
import 'package:discere/app/species_detail_loader_page.dart';
import 'package:discere/learning/decks/add_to_deck/add_to_deck_sheet.dart';
import 'package:discere/learning/decks/create_deck_page.dart';
import 'package:discere/learning/import/import_deck_page.dart';
import 'package:discere/learning/import/onboarding_deck_picker_page.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/service/navigation_tab_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/shared/ui/app_bottom_navigation_bar.dart';
import 'package:discere/shared/util/constants.dart';
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
  late final ReferenceDatabaseProvisioner _referenceDbProvisioner;
  StreamSubscription<String?>? _notificationSubscription;
  bool _hasShownReferenceDbUpdateDialog = false;

  final GlobalKey _deckFavKey = GlobalKey();
  final GlobalKey _deckEditKey = GlobalKey();
  final GlobalKey _watchlistKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    decksService = Provider.of<DecksService>(context, listen: false);
    languageService = Provider.of<LanguageService>(context, listen: false);
    _navigationTabService = Provider.of<NavigationTabService>(
      context,
      listen: false,
    );
    _referenceDbProvisioner = Provider.of<ReferenceDatabaseProvisioner>(
      context,
      listen: false,
    );
    _referenceDbProvisioner.addListener(_maybeShowReferenceDbUpdateDialog);

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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Covers the case where the background check (started unawaited from
      // bootstrap, before this page even existed) already resolved by the
      // time the listener above was attached — the listener alone would
      // otherwise miss it, since notifyListeners() already fired once.
      _maybeShowReferenceDbUpdateDialog();
      await _checkAndShowOnboarding();
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) await _checkAndShowTutorial();
    });
  }

  /// First-run entry point: a full [OnboardingDeckPickerPage] instead of a
  /// blocking modal, so picking decks (or skipping) is the only upfront
  /// choice — no proactive notification-permission ask here either, that
  /// stays purely contextual (tied to opting into iNat enrichment inside the
  /// picker's own import flow, see [runDeckImportFlow]) rather than asked
  /// before its value is obvious.
  Future<void> _checkAndShowOnboarding() async {
    final prefs = Provider.of<UserPreferencesService>(context, listen: false);
    if (prefs.hasSeenWelcomeDialog) return;

    final decks = await decksService.getAllDecks();
    if (!mounted) return;

    if (decks.isEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const OnboardingDeckPickerPage(),
        ),
      );
    }
    prefs.hasSeenWelcomeDialog = true;
  }

  /// Re-checks whether [MainScreenTutorial] should show now that the user is
  /// back on Home — called after returning from any flow that could have
  /// just made it eligible (creating/importing a deck, or finishing a first
  /// review; see [_buildFabOptions] and [HomePage.onDeckReviewReturned]).
  Future<void> _recheckTutorialAfterReturn() async {
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) await _checkAndShowTutorial();
  }

  /// True once every step of the tour — including ones added after the
  /// original two-step tour, like deckEdit — has been shown. Each such step
  /// has its own "seen" flag (see [UserPreferencesService.hasSeenTutorial]
  /// vs [UserPreferencesService.hasSeenDeckEditTutorial]) so a user who
  /// already dismissed an earlier version of the tour still gets shown
  /// what was added since, rather than the whole tour being silently
  /// skipped forever.
  bool _tutorialFullySeen(UserPreferencesService prefs) =>
      prefs.hasSeenTutorial && prefs.hasSeenDeckEditTutorial;

  Future<void> _checkAndShowTutorial() async {
    final prefs = Provider.of<UserPreferencesService>(context, listen: false);
    if (_tutorialFullySeen(prefs) || !mounted) return;
    // Deferred until after the user's first review session, so it doesn't
    // pile onto the end of first-run setup — the flashcard tutorial (what to
    // do with the deck they just picked) is the one thing immediately
    // relevant then; deck-list actions (favorite/edit/watchlist) are taught
    // once they're back on Home as a slightly-experienced user instead.
    if (!prefs.hasSeenFlashcardTutorial &&
        !prefs.hasSeenFlashcardTutorialMultipleChoice) {
      return;
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final decks = await decksService.getAllDecks();
    if (decks.isEmpty || !mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final includePreviouslySeenSteps = !prefs.hasSeenTutorial;
    prefs.hasSeenTutorial = true;
    prefs.hasSeenDeckEditTutorial = true;
    MainScreenTutorial(
      deckFavKey: _deckFavKey,
      deckEditKey: _deckEditKey,
      watchlistKey: _watchlistKey,
      includePreviouslySeenSteps: includePreviouslySeenSteps,
    ).show(context);
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _referenceDbProvisioner.removeListener(_maybeShowReferenceDbUpdateDialog);
    super.dispose();
  }

  /// Shows [_showReferenceDbUpdateDialog] once per app session, the first
  /// time a pending reference-DB update becomes known — whether that's
  /// already true by the first frame or only resolves moments later (see
  /// the two call sites in [initState]).
  void _maybeShowReferenceDbUpdateDialog() {
    if (_hasShownReferenceDbUpdateDialog || !mounted) return;
    final pending = _referenceDbProvisioner.pendingUpdate;
    if (pending == null) return;
    _hasShownReferenceDbUpdateDialog = true;
    _showReferenceDbUpdateDialog(pending, _referenceDbProvisioner.pendingUpdateOnWifi);
  }

  Future<void> _showReferenceDbUpdateDialog(
    ReferenceDbUpdateInfo pending,
    bool onWifi,
  ) async {
    final updateNow = await showReferenceDbUpdateDialog(
      context,
      compressedSizeBytes: pending.compressedSizeBytes,
      onWifi: onWifi,
    );
    if (!mounted) return;
    if (!updateNow) {
      _referenceDbProvisioner.dismissPendingUpdate();
      return;
    }
    try {
      await _referenceDbProvisioner.downloadPendingUpdate();
      if (!mounted) return;
      await maybeShowBaseRefreshPrompt(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.loc.describeError(e))));
    }
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
    return Scaffold(
      appBar: MainScreenAppBar(
        buildSpeciesDetailPage: _buildSpeciesDetailPage,
        onAddToDeck: _addToDeck,
        onOpenSettings: _openSettingsPage,
      ),
      bottomNavigationBar: AppBottomNavigationBar(watchlistKey: _watchlistKey),
      // The single-child Row is kept from before this file was split: it
      // gives the column a tight width. Removing it looks equivalent and
      // probably is, but that is a layout change, not a refactor.
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                const MainScreenEnrichmentBanner(),
                Expanded(
                  child: MainScreenTabs(
                    selectedIndex: selectedIndex,
                    buildSpeciesDetailPage: _buildSpeciesDetailPage,
                    deckFavKey: _deckFavKey,
                    deckEditKey: _deckEditKey,
                    onDeckReviewReturned: _recheckTutorialAfterReturn,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _showAddNewDeckButton(selectedIndex)
          ? MainScreenFab(
              onCreateDeck: () =>
                  _openAndRecheckTutorial((_) => const CreateDeckPage()),
              onImportDeck: () =>
                  _openAndRecheckTutorial((_) => const ImportDeckPage()),
            )
          : null,
    );
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

  /// Pushes [builder] and, on return, re-checks whether the main-screen
  /// tutorial has become eligible — creating or importing a deck is one of
  /// the things that can make it so.
  Future<void> _openAndRecheckTutorial(WidgetBuilder builder) async {
    await Navigator.push(context, MaterialPageRoute(builder: builder));
    if (!mounted) return;
    setState(() {});
    await _recheckTutorialAfterReturn();
  }

  bool _showAddNewDeckButton(int index) {
    return index == 0 || index == 1;
  }

  void _openSettingsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
  }
}
