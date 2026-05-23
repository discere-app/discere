import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'about_page.dart';
import 'diagnostics_page.dart';
import 'sources_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  static const _developerDiagnosticsUnlockedKey =
      'developer.diagnostics.unlocked';

  SharedPreferences? _prefs;
  var _developerModeUnlocked = false;
  var _developerUnlockTapCount = 0;

  @override
  void initState() {
    super.initState();
    _initPrefs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTitleTap,
          child: Text(context.loc.commonSettings),
        ),
      ),
      body: SafeArea(
        child: Consumer2<LanguageService, UserPreferencesService>(
        builder: (context, languageService, prefsService, _) {
          return SingleChildScrollView(
            padding: AppSpacing.screenPaddingAll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLanguageTile(context, languageService),
                const Divider(),
                _buildRetentionSection(context, prefsService),
                const Divider(),
                _buildSourcesTile(context),
                const Divider(),
                _buildAboutTile(context),
                if (_developerModeUnlocked) ...[
                  const Divider(),
                  _buildDiagnosticsTile(context),
                ],
              ],
            ),
          );
        },
        ),
      ),
    );
  }

  Widget _buildLanguageTile(
    BuildContext context,
    LanguageService languageService,
  ) {
    return ListTile(
      leading: const Icon(Icons.language),
      title: Text(context.loc.commonLanguage),
      trailing: DropdownButton<int>(
        value: languageService.getLanguage().value,
        onChanged: (int? newValue) {
          if (newValue != null) {
            languageService.setLanguage(newValue);
          }
        },
        items: [
          DropdownMenuItem<int>(
            value: 0,
            child: Text(context.loc.commonLanguages('de')),
          ),
          DropdownMenuItem<int>(
            value: 1,
            child: Text(context.loc.commonLanguages('en')),
          ),
        ],
      ),
    );
  }

  Widget _buildRetentionSection(
    BuildContext context,
    UserPreferencesService prefsService,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final retention = prefsService.defaultDesiredRetention;
    final pct = (retention * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lerneinstellungen', style: theme.textTheme.titleSmall),
          AppSpacing.heightS8,
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s16,
              AppSpacing.s16,
              AppSpacing.s8,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Gewünschte Retention',
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      '$pct %',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                Slider(
                  key: const Key('default_retention_slider'),
                  value: retention,
                  min: 0.70,
                  max: 0.97,
                  divisions: 27,
                  onChanged: (v) {
                    prefsService.defaultDesiredRetention = v;
                  },
                ),
                Text(
                  'Standardwert für neue Decks. In den Deck-Einstellungen einzeln überschreibbar.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourcesTile(BuildContext context) {
    return ListTile(
      key: const Key('settings_sources_tile'),
      leading: const Icon(Icons.info_outline),
      title: Text(context.loc.mainMenuSources),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const SourcesPage()));
      },
    );
  }

  Widget _buildAboutTile(BuildContext context) {
    return ListTile(
      key: const Key('settings_about_tile'),
      leading: const Icon(Icons.info_outline),
      title: Text(context.loc.mainMenuAbout),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const AboutPage()));
      },
    );
  }

  Widget _buildDiagnosticsTile(BuildContext context) {
    return ListTile(
      key: const Key('settings_diagnostics_tile'),
      leading: const Icon(Icons.bug_report_outlined),
      title: Text(context.loc.settingsDiagnostics),
      subtitle: Text(context.loc.settingsDeveloperTools),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const DiagnosticsPage()),
        );
      },
    );
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _developerModeUnlocked =
        _prefs?.getBool(_developerDiagnosticsUnlockedKey) ?? false;
    setState(() {}); // Trigger a rebuild once _prefs is initialized
  }

  Future<void> _handleTitleTap() async {
    if (_prefs == null || _developerModeUnlocked) return;
    _developerUnlockTapCount += 1;
    if (_developerUnlockTapCount < 5) return;
    await _prefs!.setBool(_developerDiagnosticsUnlockedKey, true);
    if (!mounted) return;
    setState(() {
      _developerModeUnlocked = true;
      _developerUnlockTapCount = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.loc.settingsDeveloperUnlocked)),
    );
  }
}
