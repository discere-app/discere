import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

import '../../model/biology/species_with_local_images.dart';
import '../../model/language.dart';

class FlashCardBack extends StatelessWidget {
  final SpeciesWithLocalImages speciesWithLocalImages;
  final Language language;

  const FlashCardBack({
    required this.speciesWithLocalImages,
    required this.language,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // The parent FlashCardWidget handles the Y-rotation for the flip animation.
    // We counter-rotate so the content reads correctly when shown.
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(3.14),
      child: _BackContent(
        species: speciesWithLocalImages,
        language: language,
      ),
    );
  }
}

class _BackContent extends StatelessWidget {
  final SpeciesWithLocalImages species;
  final Language language;

  const _BackContent({required this.species, required this.language});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sp = species.species;
    final commonNames = _getCommonNames();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s20, AppSpacing.s24, AppSpacing.s20, AppSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Primary Common Name (Hero) ───────────────────────────────
          Text(
            commonNames.isNotEmpty ? commonNames.first : sp.getBinomialName(),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.start,
          ),

          AppSpacing.heightS8,

          // ── Scientific Name (Subtitle) ───────────────────────────────
          Text(
            sp.getBinomialName(),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.start,
          ),

          const SizedBox(height: AppSpacing.s20),

          // ── Common Names (Expandable) ────────────────────────────────
          _SectionCard(
            child: Theme(
              // Remove the default ExpansionTile dividers
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
                childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.s16, 0, AppSpacing.s16, AppSpacing.s12),
                initiallyExpanded: true,
                leading: Icon(Icons.translate,
                    color: theme.colorScheme.primary, size: 20),
                title: Text(
                  context.loc.commonNames,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                children: commonNames.isEmpty
                    ? [
                        Text(
                          context.loc.commonNotAvailable,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        )
                      ]
                    : commonNames
                        .map(
                          (name) => Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                            child: Row(
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: 0.6),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.s10),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
              ),
            ),
          ),

          AppSpacing.heightS12,

          // ── Classification ───────────────────────────────────────────
          _SectionCard(
            child: Padding(
              padding: AppSpacing.cardPaddingAll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_tree_outlined,
                          color: theme.colorScheme.primary, size: 20),
                      AppSpacing.widthS8,
                      Text(
                        context.loc.classification,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  AppSpacing.heightS12,
                  ..._getClassificationRows(context)
                      .where((r) => r.scientific.isNotEmpty)
                      .map(
                        (row) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 90,
                                child: Text(
                                  row.label,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                    letterSpacing: 0.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      row.scientific,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                    if (row.common != null &&
                                        row.common!.isNotEmpty)
                                      Text(
                                        row.common!,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.55),
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _getCommonNames() {
    final rawNames = species.species.commonNames[language] ??
        species.species.commonNames[Language.en] ??
        '';
    if (rawNames.isEmpty) return [];
    return rawNames
        .split(';')
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList();
  }

  List<({String label, String scientific, String? common})>
      _getClassificationRows(BuildContext context) {
    final cl = species.species.classification;
    return [
      (
        label: context.loc.classificationGenus,
        scientific: cl.genusScientificName,
        common: cl.genusCommonNames[language],
      ),
      (
        label: context.loc.classificationFamily,
        scientific: cl.familyScientificName,
        common: cl.familyCommonNames[language],
      ),
      (
        label: context.loc.classificationOrder,
        scientific: cl.orderScientificName,
        common: cl.orderCommonNames[language],
      ),
      (
        label: context.loc.classificationClass,
        scientific: cl.classScientificName,
        common: cl.classCommonNames[language],
      ),
      if (cl.superClass != null && cl.superClass!.isNotEmpty)
        (
          label: context.loc.classificationSuperClass,
          scientific: cl.superClass!,
          common: null,
        ),
    ];
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.07)),
      ),
      child: child,
    );
  }
}
