import 'package:discere/app/about_page.dart';
import 'package:discere/app/diagnostics_page.dart';
import 'package:discere/app/sources_page.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:discere/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  SharedPreferences? _prefs;
  var _developerModeUnlocked = false;

  @override
  void initState() {
    super.initState();
    _initPrefs();
  }

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
                  _buildLearningSection(context, languageService, prefsService),
                  Divider(color: context.sectionBorderColor),
                  _buildSourcesTile(context),
                  Divider(color: context.sectionBorderColor),
                  _buildAboutTile(context),
                  if (_developerModeUnlocked) ...[
                    Divider(color: context.sectionBorderColor),
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

  Widget _buildLearningSection(
    BuildContext context,
    LanguageService languageService,
    UserPreferencesService prefsService,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final retention = prefsService.defaultDesiredRetention;
    final pct = (retention * 100).round();
    final time = TimeOfDay(
      hour: prefsService.notificationHour,
      minute: prefsService.notificationMinute,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.loc.settingsLearningTitle,
          style: theme.textTheme.titleSmall,
        ),
        AppSpacing.heightS8,
        SectionCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.loc.commonLanguage,
                      style: theme.textTheme.titleMedium,
                    ),
                    DropdownButton<int>(
                      key: const Key('language_dropdown'),
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
                  ],
                ),
                AppSpacing.heightS8,
                Text(
                  context.loc.settingsLanguageDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                AppSpacing.heightS16,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.loc.settingsRetentionLabel,
                      style: theme.textTheme.titleMedium,
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
                  context.loc.settingsRetentionDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                AppSpacing.heightS16,
                InkWell(
                  key: const Key('notification_time_tile'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () =>
                      _pickNotificationTime(context, prefsService, time),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.loc.settingsNotificationTimeLabel,
                              style: theme.textTheme.titleMedium,
                            ),
                            AppSpacing.heightS8,
                            Text(
                              context.loc.settingsNotificationTimeDescription,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        time.format(context),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickNotificationTime(
    BuildContext context,
    UserPreferencesService prefsService,
    TimeOfDay currentTime,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: currentTime,
    );
    if (picked == null || picked == currentTime) return;

    prefsService.notificationHour = picked.hour;
    prefsService.notificationMinute = picked.minute;

    if (!context.mounted) return;
    await context.read<FlashcardService>().rescheduleNotifications(
      notificationTitle: context.loc.notificationDailyTitle,
      notificationBodyBuilder: (count) =>
          context.loc.notificationDailyBody(count),
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
      onTap: () async {
        // Developer mode is unlocked by tapping the version number on
        // AboutPage — re-read the preference on return since this page's
        // own state isn't recreated by a push/pop round trip.
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const AboutPage()));
        await _refreshDeveloperModeUnlocked();
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
        _prefs?.getBool(AppConstants.developerDiagnosticsUnlockedPrefKey) ??
        false;
    setState(() {}); // Trigger a rebuild once _prefs is initialized
  }

  Future<void> _refreshDeveloperModeUnlocked() async {
    if (_developerModeUnlocked) return;
    final unlocked =
        _prefs?.getBool(AppConstants.developerDiagnosticsUnlockedPrefKey) ??
        false;
    if (!mounted || !unlocked) return;
    setState(() {
      _developerModeUnlocked = true;
    });
  }
}
