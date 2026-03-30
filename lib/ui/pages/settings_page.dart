import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
            _buildSourcesTile(context),
          ],
        ),
      ),
    );
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



  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {}); // Trigger a rebuild once _prefs is initialized
  }

}
