import 'package:discere/catalog/model/source.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

final _log = Logger.forType(SourcesPage);

/// Bespoke accent palette for this page's hero/credits look — has no
/// equivalent role in the app's shared Ocean theme, so it's centralized
/// here instead of duplicated as inline hex literals.
class _HeroPalette {
  static const Color accent = Color(0xFF81cfff);
  static const Color accentContainer = Color(0xFF0079a8);
  static const Color onAccent = Color(0xFF00344b);
  static const Color mutedText = Color(0xFFbfc7d1);
  static const Color cardBackground = Color(0xFF11212e);
  static const Color chipBackground = Color(0xFF263644);
  static const Color licenseItemBackground = Color(0xFF01101b);
  static const Color divider = Color(0x33404850);
}

class SourcesPage extends StatelessWidget {
  const SourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final sourceService = context.read<SourceService>();

    return Scaffold(
      appBar: AppBar(title: Text(loc.sourcesTitle)),
      body: SafeArea(
        child: FutureBuilder<List<Source>>(
          future: sourceService.getAllSources(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(
                child: Text(
                  '${loc.error}: ${loc.describeError(snapshot.error)}',
                ),
              );
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(child: Text(loc.sourcesNoData));
            }

            final sources = snapshot.data!;
            // Request distinct licenses
            return FutureBuilder<List<({String key, String? licenseUrl})>>(
              future: sourceService.getDistinctLicenses(),
              builder: (context, licenseSnapshot) {
                final licenses = licenseSnapshot.data ?? [];

                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s24,
                        vertical: AppSpacing.s32,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeroSection(context, loc),
                            const SizedBox(height: AppSpacing.s48),
                            _buildSourcesGrid(context, sources, loc),
                            const SizedBox(height: AppSpacing.s80),
                            _buildLicensesFooter(context, licenses, loc),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context, AppLocalizations loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.sourcesHeroTitle,
          key: const Key('sources_hero_title'),
          style: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w800,
            height: 1.1,
            color: _HeroPalette.accent,
          ),
        ),
        AppSpacing.heightS16,
        Text(
          loc.sourcesHeroDescription,
          style: const TextStyle(
            fontSize: 18,
            height: 1.6,
            color: _HeroPalette.mutedText,
          ),
        ),
      ],
    );
  }

  Widget _buildSourcesGrid(
    BuildContext context,
    List<Source> sources,
    AppLocalizations loc,
  ) {
    // Determine cross axis count based on screen width
    final isDesktop = MediaQuery.of(context).size.width > 600;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isDesktop ? 2 : 1,
        mainAxisSpacing: AppSpacing.s32,
        crossAxisSpacing: AppSpacing.s32,
        childAspectRatio: isDesktop ? 1.0 : 0.8,
        mainAxisExtent: 350,
      ),
      itemCount: sources.length,
      itemBuilder: (context, index) {
        return _SourceCard(source: sources[index], loc: loc);
      },
    );
  }

  Widget _buildLicensesFooter(
    BuildContext context,
    List<({String key, String? licenseUrl})> licenses,
    AppLocalizations loc,
  ) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.only(top: AppSpacing.s48),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _HeroPalette.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.sourcesAboutLicensesTitle,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: onSurface,
            ),
          ),
          AppSpacing.heightS16,
          Text(
            loc.sourcesAboutLicensesDescription,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: _HeroPalette.mutedText,
            ),
          ),
          AppSpacing.heightS24,
          Wrap(
            spacing: AppSpacing.s24,
            runSpacing: AppSpacing.s24,
            children: licenses
                .map((l) => _buildLicenseItem(context, l, loc))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLicenseItem(
    BuildContext context,
    ({String key, String? licenseUrl}) license,
    AppLocalizations loc,
  ) {
    String description = '';
    if (license.key == 'CC BY 4.0' || license.key == 'CC BY / CC0') {
      description = loc.sourcesLicenseCcBy;
    } else if (license.key == 'CC BY-NC 4.0' || license.key.contains('NC')) {
      description = loc.sourcesLicenseCcByNc;
    } else if (license.key == 'ARR') {
      description = loc.sourcesLicenseArr;
    }

    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      width: 160,
      padding: AppSpacing.cardPaddingAll,
      decoration: BoxDecoration(
        color: _HeroPalette.licenseItemBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            license.key,
            style: const TextStyle(
              fontSize: 10,
              color: _HeroPalette.accent,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          AppSpacing.heightS4,
          Text(
            description,
            style: TextStyle(
              fontSize: 12,
              color: onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  final Source source;
  final AppLocalizations loc;

  const _SourceCard({required this.source, required this.loc});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      key: Key('source_card_${source.id}'),
      padding: const EdgeInsets.all(AppSpacing.s32),
      decoration: BoxDecoration(
        color: _HeroPalette.cardBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  source.category.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _HeroPalette.accent,
                    letterSpacing: 1.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                  vertical: AppSpacing.s4,
                ),
                decoration: BoxDecoration(
                  color: _HeroPalette.chipBackground,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  source.licenseKey,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _HeroPalette.mutedText,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.heightS24,
          Text(
            source.name,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          AppSpacing.heightS16,
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                source.citation,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: onSurface.withValues(alpha: 0.8),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
          AppSpacing.heightS24,
          SizedBox(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_HeroPalette.accent, _HeroPalette.accentContainer],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _HeroPalette.accent.withValues(alpha: 0.2),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () async {
                    final uri = Uri.parse(source.url);
                    _log.debug('Opening source website: $uri');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  child: Padding(
                    padding: AppSpacing.buttonPaddingVertical,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          loc.sourcesVisitWebsite,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _HeroPalette.onAccent,
                          ),
                        ),
                        AppSpacing.widthS8,
                        const Icon(
                          Icons.open_in_new,
                          size: 16,
                          color: _HeroPalette.onAccent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
