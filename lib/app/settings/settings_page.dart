import 'package:discere/app/diagnostics/diagnostics_page.dart';
import 'package:discere/app/info/about_page.dart';
import 'package:discere/app/info/sources_page.dart';
import 'package:discere/app/settings/widgets/settings_learning_section.dart';
import 'package:discere/app/settings/widgets/settings_navigation_tile.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:discere/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SharedPreferences? _prefs;
  var _developerModeUnlocked = false;

  @override
  void initState() {
    super.initState();
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _developerModeUnlocked = _isDeveloperModeUnlocked();
    if (mounted) setState(() {});
  }

  bool _isDeveloperModeUnlocked() =>
      _prefs?.getBool(AppConstants.developerDiagnosticsUnlockedPrefKey) ??
      false;

  /// Developer mode is unlocked by tapping the version number on
  /// [AboutPage], so the flag can change while this page is merely
  /// backgrounded — its own state is not recreated by a push/pop round trip.
  Future<void> _refreshDeveloperModeUnlocked() async {
    if (_developerModeUnlocked || !_isDeveloperModeUnlocked()) return;
    if (!mounted) return;
    setState(() => _developerModeUnlocked = true);
  }

  Future<void> _open(WidgetBuilder builder) =>
      Navigator.of(context).push(MaterialPageRoute(builder: builder));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.loc.commonSettings)),
      body: SafeArea(
        child: Consumer2<LanguageService, UserPreferencesService>(
          builder: (context, languageService, prefsService, _) {
            return SingleChildScrollView(
              padding: AppSpacing.screenPaddingAll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsLearningSection(
                    languageService: languageService,
                    prefsService: prefsService,
                  ),
                  Divider(color: context.sectionBorderColor),
                  SettingsNavigationTile(
                    key: const Key('settings_sources_tile'),
                    icon: Icons.info_outline,
                    title: context.loc.mainMenuSources,
                    onTap: () => _open((_) => const SourcesPage()),
                  ),
                  Divider(color: context.sectionBorderColor),
                  SettingsNavigationTile(
                    key: const Key('settings_about_tile'),
                    icon: Icons.info_outline,
                    title: context.loc.mainMenuAbout,
                    onTap: () async {
                      await _open((_) => const AboutPage());
                      await _refreshDeveloperModeUnlocked();
                    },
                  ),
                  if (_developerModeUnlocked) ...[
                    Divider(color: context.sectionBorderColor),
                    SettingsNavigationTile(
                      key: const Key('settings_diagnostics_tile'),
                      icon: Icons.bug_report_outlined,
                      title: context.loc.settingsDiagnostics,
                      subtitle: context.loc.settingsDeveloperTools,
                      onTap: () => _open((_) => const DiagnosticsPage()),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
