import 'package:discere/app/info/widgets/info_section.dart';
import 'package:discere/app/info/widgets/participate_item.dart';
import 'package:discere/app/info/widgets/repository_tile.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const _unlockTapThreshold = 5;

  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();
  int _versionTapCount = 0;
  bool _developerModeUnlocked = false;

  @override
  void initState() {
    super.initState();
    _loadDeveloperModeUnlocked();
  }

  Future<void> _loadDeveloperModeUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _developerModeUnlocked =
          prefs.getBool(AppConstants.developerDiagnosticsUnlockedPrefKey) ??
          false;
    });
  }

  Future<void> _handleVersionTap() async {
    if (_developerModeUnlocked) return;
    _versionTapCount += 1;
    if (_versionTapCount < _unlockTapThreshold) return;
    _versionTapCount = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      AppConstants.developerDiagnosticsUnlockedPrefKey,
      true,
    );
    if (!mounted) return;
    setState(() {
      _developerModeUnlocked = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.loc.settingsDeveloperUnlocked)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.loc.aboutTitle)),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.screenPaddingAll,
          children: [
            InfoSection(
              icon: Icons.person_outline,
              title: context.loc.aboutDeveloperTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppConstants.developerName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  AppSpacing.heightS8,
                  Text(context.loc.aboutDeveloperDescription),
                ],
              ),
            ),
            AppSpacing.heightS16,
            InfoSection(
              icon: Icons.apps_outlined,
              title: context.loc.aboutAppTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.loc.aboutAppDescription),
                  AppSpacing.heightS8,
                  FutureBuilder<PackageInfo>(
                    future: _packageInfo,
                    builder: (context, snapshot) {
                      final version = snapshot.data?.version ?? '—';
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _handleVersionTap,
                        child: Text(
                          context.loc.aboutVersion(version),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            AppSpacing.heightS16,
            InfoSection(
              icon: Icons.feedback_outlined,
              title: context.loc.aboutFeedbackTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.loc.aboutFeedbackDescription),
                  AppSpacing.heightS12,
                  FilledButton.icon(
                    onPressed: () => _launchMail(context),
                    icon: const Icon(Icons.mail_outline),
                    label: const Text(AppConstants.feedbackEmail),
                  ),
                ],
              ),
            ),
            AppSpacing.heightS16,
            InfoSection(
              icon: Icons.group_add_outlined,
              title: context.loc.aboutParticipateTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ParticipateItem(
                    icon: Icons.style_outlined,
                    title: context.loc.aboutPublicDecksTitle,
                    description: context.loc.aboutPublicDecksDescription,
                  ),
                  AppSpacing.heightS16,
                  ParticipateItem(
                    icon: Icons.image_outlined,
                    title: context.loc.aboutContributeImagesTitle,
                    description: context.loc.aboutContributeImagesDescription,
                  ),
                  AppSpacing.heightS16,
                  ParticipateItem(
                    icon: Icons.code,
                    title: context.loc.aboutDevelopTogetherTitle,
                    description: context.loc.aboutDevelopTogetherDescription,
                  ),
                  AppSpacing.heightS16,
                  Divider(color: colorScheme.outlineVariant),
                  RepositoryTile(
                    title: context.loc.aboutAppRepositoryTitle,
                    description: context.loc.aboutAppRepositoryDescription,
                    url: AppConstants.repositoryUrl,
                  ),
                  RepositoryTile(
                    title: context.loc.aboutDataRepositoryTitle,
                    description: context.loc.aboutDataRepositoryDescription,
                    url: AppConstants.dataRepositoryUrl,
                  ),
                ],
              ),
            ),
            AppSpacing.heightS16,
            InfoSection(
              icon: Icons.description_outlined,
              title: context.loc.aboutLicensesTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.loc.aboutLicensesDescription),
                  AppSpacing.heightS12,
                  OutlinedButton.icon(
                    onPressed: () => _showLicenses(context),
                    icon: const Icon(Icons.description_outlined),
                    label: Text(context.loc.aboutLicensesButton),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchMail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppConstants.feedbackEmail,
      queryParameters: {'subject': context.loc.aboutFeedbackEmailSubject},
    );
    await launchUrl(uri);
  }

  void _showLicenses(BuildContext context) {
    showLicensePage(context: context, applicationName: 'Discere');
  }
}
