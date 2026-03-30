import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../model/language.dart';
import '../../service/common/language_service.dart';
import 'sources_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _initPrefs();
  }

  @override
  Widget build(BuildContext context) {
    if (_prefs == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.loc.commonSettings),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._buildLanguageFieldGroup(context),
            const Divider(height: 32),
            _buildSourcesTile(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLanguageFieldGroup(BuildContext context) {
    final languageMap = Map.fromEntries(
      Language.values.map(
        (lang) => MapEntry(
          context.loc.commonLanguages(lang.name),
          lang.value,
        ),
      ),
    );

    return [
      _buildGroupTitle(context.loc.commonLanguage),
      _buildSelect(LanguageService.sharedPreferencesLanguageKey,
          context.loc.commonLanguage, languageMap),
    ];
  }

  Widget _buildSourcesTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text(context.loc.mainMenuSources),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const SourcesPage()),
        );
      },
    );
  }

  Widget _buildGroupTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }

  Widget _buildSelect(
      String sharedPrefsKey, String title, Map<String, int> options) {
    int selectedValue = _prefs?.getInt(sharedPrefsKey) ?? options.values.first;

    return ListTile(
      title: Text(title),
      trailing: DropdownButton<int>(
        value: selectedValue,
        onChanged: (int? newValue) {
          if (newValue == null) return;
          if (sharedPrefsKey == LanguageService.sharedPreferencesLanguageKey) {
            Provider.of<LanguageService>(context, listen: false)
                .setLanguage(newValue);
          } else {
            _saveIntValue(sharedPrefsKey, newValue);
          }
          setState(() {
            selectedValue = newValue;
          });
        },
        items: options.entries.map<DropdownMenuItem<int>>((entry) {
          return DropdownMenuItem<int>(
            value: entry.value,
            child: Text(entry.key),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {}); // Trigger a rebuild once _prefs is initialized
  }

  Future<void> _saveIntValue(String key, int value) async {
    await _prefs?.setInt(key, value);
  }
}
