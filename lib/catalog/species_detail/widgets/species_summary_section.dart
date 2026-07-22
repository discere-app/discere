import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/service/species_inat_metadata_service.dart';
import 'package:discere/external/wikipedia/wikipedia_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shows the species' Wikipedia lead-paragraph summary, fetched directly
/// from Wikipedia (not via iNaturalist) in the current app language, with a
/// fallback to the article's own language if no translation exists.
class SpeciesSummarySection extends StatefulWidget {
  final String speciesId;
  final Language language;

  const SpeciesSummarySection({
    super.key,
    required this.speciesId,
    required this.language,
  });

  @override
  State<SpeciesSummarySection> createState() => _SpeciesSummarySectionState();
}

class _SpeciesSummarySectionState extends State<SpeciesSummarySection> {
  late Future<WikipediaSummary?> _futureSummary;

  @override
  void initState() {
    super.initState();
    _futureSummary = _loadSummary();
  }

  @override
  void didUpdateWidget(covariant SpeciesSummarySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speciesId != widget.speciesId ||
        oldWidget.language != widget.language) {
      _futureSummary = _loadSummary();
    }
  }

  Future<WikipediaSummary?> _loadSummary() async {
    final metadataService = Provider.of<SpeciesInatMetadataService>(
      context,
      listen: false,
    );
    final wikipediaUrl = await metadataService.ensureCached(
      widget.speciesId,
      ExternalIdProvider.wikipedia,
    );
    if (wikipediaUrl == null || wikipediaUrl.isEmpty) return null;
    if (!mounted) return null;

    final wikipediaService = Provider.of<WikipediaService>(
      context,
      listen: false,
    );
    return wikipediaService.getSummary(
      wikipediaUrl: wikipediaUrl,
      localeCode: widget.language.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<WikipediaSummary?>(
      future: _futureSummary,
      builder: (context, snapshot) {
        final summary = snapshot.data;
        if (summary == null || summary.extract.isEmpty) {
          return const SizedBox.shrink();
        }

        return SectionCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.loc.speciesDetailWikipediaSummaryTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(summary.extract, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        );
      },
    );
  }
}
