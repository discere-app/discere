import 'package:discere/app/info/widgets/sources_grid.dart';
import 'package:discere/app/info/widgets/sources_hero_section.dart';
import 'package:discere/app/info/widgets/sources_licenses_footer.dart';
import 'package:discere/catalog/model/source.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Credits screen: the upstream datasets the reference DB is built from,
/// their citations, and what their licences allow.
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
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('${loc.error}: ${loc.describeError(snapshot.error)}'),
              );
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(child: Text(loc.sourcesNoData));
            }
            return _Body(sources: snapshot.data!, loc: loc);
          },
        ),
      ),
    );
  }
}

/// The licence list loads separately from the sources, so the page can show
/// the cards without waiting on it — an empty list until it arrives just
/// means the footer has nothing to explain yet.
class _Body extends StatelessWidget {
  final List<Source> sources;
  final AppLocalizations loc;

  const _Body({required this.sources, required this.loc});

  @override
  Widget build(BuildContext context) {
    final sourceService = context.read<SourceService>();

    return FutureBuilder<List<({String key, String? licenseUrl})>>(
      future: sourceService.getDistinctLicenses(),
      builder: (context, licenseSnapshot) {
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
                    SourcesHeroSection(loc: loc),
                    const SizedBox(height: AppSpacing.s48),
                    SourcesGrid(sources: sources, loc: loc),
                    const SizedBox(height: AppSpacing.s80),
                    SourcesLicensesFooter(
                      licenses: licenseSnapshot.data ?? const [],
                      loc: loc,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
