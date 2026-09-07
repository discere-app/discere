import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The three settings that change how reviewing works: interface language,
/// the default retention new decks are created with, and when the daily
/// reminder fires.
class SettingsLearningSection extends StatelessWidget {
  final LanguageService languageService;
  final UserPreferencesService prefsService;

  const SettingsLearningSection({
    required this.languageService,
    required this.prefsService,
    super.key,
  });

  /// Rescheduling has to happen here rather than on the next app start:
  /// the notification is already queued with the old time, and nothing else
  /// would move it.
  Future<void> _pickNotificationTime(
    BuildContext context,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final retention = prefsService.defaultDesiredRetention;
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
                      onChanged: (value) {
                        if (value != null) languageService.setLanguage(value);
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
                      '${(retention * 100).round()} %',
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
                  onChanged: (value) =>
                      prefsService.defaultDesiredRetention = value,
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
                  onTap: () => _pickNotificationTime(context, time),
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
}
