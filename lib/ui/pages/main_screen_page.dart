
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

class MainScreenPage extends StatefulWidget {
  const MainScreenPage({super.key});

  @override
  State<MainScreenPage> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreenPage> {
  late final DecksService decksService;
  late final LanguageService languageService;
  var selectedIndex = 0;

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
          title: const Text('Discere AquaLife'),
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
            ? FloatingActionButton(
                onPressed: () => _showCreateDeckDialog(context),
                child: const Icon(Icons.add),
              )
            : null, // floating button nicht anzeigen
      );
    });
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

    resolvePlatformSpecificImplementation?.requestNotificationsPermission();
    resolvePlatformSpecificImplementation?.requestExactAlarmsPermission();
  }

  void _openSettingsPage() {
    Navigator.push(
        context, MaterialPageRoute(builder: (context) => const SettingsPage()));
  }

  void _showCreateDeckDialog(BuildContext context) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    final TextEditingController speciesController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return CreateDeckDialogWidget(
            nameController: nameController,
            descriptionController: descriptionController,
            speciesController: speciesController,
            decksService: decksService);
      },
    );
  }
}

class CreateDeckDialogWidget extends StatelessWidget {
  const CreateDeckDialogWidget({
    super.key,
    required this.nameController,
    required this.descriptionController,
    required this.speciesController,
    required this.decksService,
  });

  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController speciesController;
  final DecksService decksService;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.loc.createNewDeckTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            decoration: InputDecoration(labelText: context.loc.commonName),
          ),
          TextField(
            controller: descriptionController,
            decoration:
                InputDecoration(labelText: context.loc.commonDescription),
          ),
          TextField(
            controller: speciesController,
            decoration: InputDecoration(
                labelText: context.loc.createNewDeckSpeciesScientificNames),
            maxLines: 4,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(context.loc.commonCancel),
        ),
        TextButton(
          onPressed: () {
            final String name = nameController.text;
            final String description = descriptionController.text;
            final List<String> species =
                speciesController.text.split('\n').toList();

            decksService.createDeckBySpeciesScientificNames(
                name, description, species);

            Navigator.of(context).pop();
          },
          child: Text(context.loc.commonCreate),
        ),
      ],
    );
  }
}
