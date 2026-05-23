import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:discere/shared/util/logger.dart';

import 'package:discere/catalog/model/source.dart';
import 'package:discere/catalog/service/source_service.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';

final _log = Logger.forType(SourcesPage);

class SourcesPage extends StatelessWidget {
  const SourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final sourceService = context.read<SourceService>();

    return Scaffold(
      backgroundColor: const Color(0xFF041521),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C1D29),
        elevation: 0,
        title: Text(
          loc.sourcesTitle,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<List<Source>>(
        future: sourceService.getAllSources(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No sources available.'));
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
            color: Color(0xFF81cfff),
          ),
        ),
        AppSpacing.heightS16,
        Text(
          loc.sourcesHeroDescription,
          style: const TextStyle(
            fontSize: 18,
            height: 1.6,
            color: Color(0xFFbfc7d1),
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
    return Container(
      padding: const EdgeInsets.only(top: AppSpacing.s48),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x33404850))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.sourcesAboutLicensesTitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          AppSpacing.heightS16,
          Text(
            loc.sourcesAboutLicensesDescription,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFFbfc7d1),
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

    return Container(
      width: 160,
      padding: AppSpacing.cardPaddingAll,
      decoration: BoxDecoration(
        color: const Color(0xFF01101b),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            license.key,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF81cfff),
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          AppSpacing.heightS4,
          Text(
            description,
            style: const TextStyle(fontSize: 12, color: Color(0xB3FFFFFF)),
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
    return Container(
      key: Key('source_card_${source.id}'),
      padding: const EdgeInsets.all(AppSpacing.s32),
      decoration: BoxDecoration(
        color: const Color(0xFF11212e),
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
                    color: Color(0xFF81cfff),
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
                  color: const Color(0xFF263644),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  source.licenseKey,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFbfc7d1),
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.heightS24,
          Text(
            source.name,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          AppSpacing.heightS16,
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                source.citation,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Color(0xCCFFFFFF),
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
                  colors: [
                    Color(0xFF81cfff), // primary
                    Color(0xFF0079a8), // primary-container
                  ],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x3381cfff),
                    blurRadius: 32,
                    offset: Offset(0, 12),
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
                            color: Color(0xFF00344b), // on-primary
                          ),
                        ),
                        AppSpacing.widthS8,
                        const Icon(
                          Icons.open_in_new,
                          size: 16,
                          color: Color(0xFF00344b),
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
