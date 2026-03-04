
import 'package:discere/extensions/localization_extension.dart';
import 'package:discere/ui/pages/settings_page.dart';
import 'package:discere/ui/pages/watchlist_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';

import '../../persistence/search_repository.dart';
import '../../service/common/language_service.dart';
import '../../service/learning/decks_service.dart';
import '../search_species_delegate.dart';
import 'favorites_page.dart';
import 'home_page.dart';
import 'create_deck_page.dart';
import 'import_deck_page.dart';

class MainScreenPage extends StatefulWidget {
  const MainScreenPage({super.key});

  @override
  State<MainScreenPage> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreenPage> {
  late final DecksService decksService;
  late final LanguageService languageService;
  var selectedIndex = 0;
  bool _fabExpanded = false;

  @override
  void initState() {
    super.initState();
    decksService = Provider.of<DecksService>(context, listen: false);
    languageService = Provider.of<LanguageService>(context, listen: false);
    _checkPermissions();
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
        page = const WatchListPage();
      default:
        throw UnimplementedError('no widget for $selectedIndex');
    }

    return LayoutBuilder(builder: (context, constraints) {
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
                        languageService),
                  );
                }),
            IconButton(
                onPressed: _openSettingsPage, icon: const Icon(Icons.settings))
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: [
            BottomNavigationBarItem(
              icon: selectedIndex == 0
                  ? const Icon(Icons.home)
                  : const Icon(Icons.home_outlined), // Home
              label: context.loc.navigationHome,
            ),
            BottomNavigationBarItem(
              icon: selectedIndex == 1
                  ? const Icon(Icons.favorite)
                  : const Icon(Icons.favorite_border),
              label: context.loc.navigationFavourites,
            ),
            BottomNavigationBarItem(
                icon: selectedIndex == 2
                    ? const Icon(Icons.format_list_bulleted)
                    : const Icon(Icons.format_list_bulleted_outlined),
                label: context.loc.navigationWatchlist),
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
              child: Container(
                child: page,
              ),
            ),
          ],
        ),
        floatingActionButton: _showAddNewDeckButton(selectedIndex)
            ? _buildFab(context)
            : null,
      );
    });
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
        label: context.loc.createNewDeckTitle,
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
      const SizedBox(height: 12),
      _FabOption(
        icon: Icons.qr_code_scanner,
        label: context.loc.importDeckTitle,
        heroTag: 'fab-import',
        onPressed: () async {
          setState(() => _fabExpanded = false);
          await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const ImportDeckPage()),
          );
          // Refresh home page decks after import
          if (mounted) setState(() {});
        },
      ),
      const SizedBox(height: 12),
    ];
  }

  bool _showAddNewDeckButton(int index) {
    return index == 0 || index == 1;
  }

  Future<void> _checkPermissions() async {
    FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    var resolvePlatformSpecificImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await resolvePlatformSpecificImplementation?.requestNotificationsPermission();
  }

  void _openSettingsPage() {
    Navigator.push(
        context, MaterialPageRoute(builder: (context) => const SettingsPage()));
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 4,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.small(
          heroTag: heroTag,
          onPressed: onPressed,
          child: Icon(icon),
        ),
      ],
    );
  }
}

