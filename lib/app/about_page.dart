import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const _developerName = 'Fabian Eberle';
  static const _feedbackEmail = 'dev.feberle@gmail.com';
  static const _appRepositoryUrl = 'https://github.com/feberle/discere';
  static const _dataRepositoryUrl = 'https://github.com/feberle/discere-data';

  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.loc.aboutTitle)),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.screenPaddingAll,
        children: [
          _InfoSection(
            icon: Icons.person_outline,
            title: context.loc.aboutDeveloperTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _developerName,
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
          _InfoSection(
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
                    return Text(
                      context.loc.aboutVersion(version),
                      style: Theme.of(context).textTheme.bodySmall,
                    );
                  },
                ),
              ],
            ),
          ),
          AppSpacing.heightS16,
          _InfoSection(
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
                  label: const Text(_feedbackEmail),
                ),
              ],
            ),
          ),
          AppSpacing.heightS16,
          _InfoSection(
            icon: Icons.group_add_outlined,
            title: context.loc.aboutParticipateTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ParticipateItem(
                  icon: Icons.style_outlined,
                  title: context.loc.aboutPublicDecksTitle,
                  description: context.loc.aboutPublicDecksDescription,
                ),
                AppSpacing.heightS16,
                _ParticipateItem(
                  icon: Icons.image_outlined,
                  title: context.loc.aboutContributeImagesTitle,
                  description: context.loc.aboutContributeImagesDescription,
                ),
                AppSpacing.heightS16,
                _ParticipateItem(
                  icon: Icons.code,
                  title: context.loc.aboutDevelopTogetherTitle,
                  description: context.loc.aboutDevelopTogetherDescription,
                ),
                AppSpacing.heightS16,
                Divider(color: colorScheme.outlineVariant),
                _RepositoryTile(
                  title: context.loc.aboutAppRepositoryTitle,
                  description: context.loc.aboutAppRepositoryDescription,
                  url: _appRepositoryUrl,
                ),
                _RepositoryTile(
                  title: context.loc.aboutDataRepositoryTitle,
                  description: context.loc.aboutDataRepositoryDescription,
                  url: _dataRepositoryUrl,
                ),
              ],
            ),
          ),
          AppSpacing.heightS16,
          _InfoSection(
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
      path: _feedbackEmail,
      queryParameters: {'subject': context.loc.aboutFeedbackEmailSubject},
    );
    await launchUrl(uri);
  }

  void _showLicenses(BuildContext context) {
    showLicensePage(context: context, applicationName: 'Discere');
  }
}

class _ParticipateItem extends StatelessWidget {
  const _ParticipateItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colorScheme.primary),
        AppSpacing.widthS12,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              AppSpacing.heightS4,
              Text(description),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: AppSpacing.paddingS16All,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary),
                AppSpacing.widthS12,
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            AppSpacing.heightS12,
            DefaultTextStyle.merge(
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _RepositoryTile extends StatelessWidget {
  const _RepositoryTile({
    required this.title,
    required this.description,
    required this.url,
  });

  final String title;
  final String description;
  final String url;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.code),
      title: Text(title),
      subtitle: Text(description),
      trailing: Tooltip(
        message: context.loc.aboutOpenLinkTooltip,
        child: const Icon(Icons.open_in_new),
      ),
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    );
  }
}
