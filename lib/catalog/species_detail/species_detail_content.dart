import 'package:discere/catalog/common/taxon_identity/identity_header.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/species_detail/species_detail_presenter.dart';
import 'package:discere/catalog/species_detail/widgets/species_common_names_section.dart';
import 'package:discere/catalog/species_detail/widgets/species_conservation_status_section.dart';
import 'package:discere/catalog/species_detail/widgets/species_decks_section.dart';
import 'package:discere/catalog/species_detail/widgets/species_deprecated_banner.dart';
import 'package:discere/catalog/species_detail/widgets/species_external_links.dart';
import 'package:discere/catalog/species_detail/widgets/species_facts_section.dart';
import 'package:discere/catalog/species_detail/widgets/species_image_refresh_indicator.dart';
import 'package:discere/catalog/species_detail/widgets/species_media_carousel.dart';
import 'package:discere/catalog/species_detail/widgets/species_native_regions_section.dart';
import 'package:discere/catalog/species_detail/widgets/species_scientific_classification_section.dart';
import 'package:discere/catalog/species_detail/widgets/species_summary_section.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class SpeciesDetailContent extends StatelessWidget {
  final SpeciesWithLocalImages species;

  /// The language the species' names are shown in: the primary name, the
  /// common-name list and the common names in the classification.
  final Language nameLanguage;

  /// Switches [nameLanguage], placed in the header.
  final Widget languageSelector;

  /// The language the Wikipedia summary is fetched in. Kept apart from
  /// [nameLanguage] because looking at the names in another language must
  /// not swap the article text underneath.
  final Language summaryLanguage;
  final List<String> deckNames;
  final bool isRefreshingImages;
  final void Function(SearchResult)? onNavigateToTaxon;
  static const SpeciesDetailPresenter _presenter = SpeciesDetailPresenter();

  const SpeciesDetailContent({
    super.key,
    required this.species,
    required this.nameLanguage,
    required this.languageSelector,
    required this.summaryLanguage,
    this.deckNames = const [],
    this.isRefreshingImages = false,
    this.onNavigateToTaxon,
  });

  @override
  Widget build(BuildContext context) {
    final viewData = _presenter.present(
      species.species,
      nameLanguage,
      context.loc,
    );
    final identity = viewData.identity;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            AppSpacing.s16,
            AppSpacing.s16,
            AppSpacing.s24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (viewData.isDeprecated) const SpeciesDeprecatedBanner(),
              IdentityHeader(
                identity: identity,
                languageSelector: languageSelector,
              ),
              const SizedBox(height: AppSpacing.s16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: Stack(
                  key: ValueKey(
                    '${species.species.pictures.length}_${species.localPictures.length}',
                  ),
                  children: [
                    SpeciesMediaCarousel(
                      key: const Key('image'),
                      speciesWithLocalImages: species,
                      height: (constraints.maxWidth * 0.64).clamp(180.0, 260.0),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    if (isRefreshingImages)
                      const Positioned(
                        top: AppSpacing.s12,
                        left: AppSpacing.s12,
                        child: SpeciesImageRefreshIndicator(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s16),
              SpeciesCommonNamesSection(commonNames: identity.commonNames),
              const SizedBox(height: AppSpacing.s12),
              SpeciesScientificClassificationSection(
                rows: viewData.classificationRows,
                onNavigate: onNavigateToTaxon,
              ),
              const SizedBox(height: AppSpacing.s16),
              SpeciesFactsSection(section: viewData.factsSection),
              const SizedBox(height: AppSpacing.s16),
              SpeciesConservationStatusSection(speciesId: species.species.id),
              if (viewData.nativeRegionsSection != null) ...[
                const SizedBox(height: AppSpacing.s16),
                SpeciesNativeRegionsSection(
                  section: viewData.nativeRegionsSection!,
                ),
              ],
              if (deckNames.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s16),
                SpeciesDecksSection(deckNames: deckNames),
              ],
              const SizedBox(height: AppSpacing.s16),
              SpeciesSummarySection(
                speciesId: species.species.id,
                language: summaryLanguage,
              ),
              const SizedBox(height: AppSpacing.s20),
              SpeciesExternalLinks(species: species.species),
            ],
          ),
        );
      },
    );
  }
}
