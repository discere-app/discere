import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

import '../../model/biology/species_with_local_images.dart';
import '../../model/language.dart';
import '../../theme/app_spacing.dart';

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
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(3.14),
      child: SpeciesInfoContent(
        species: speciesWithLocalImages,
        language: language,
      ),
    );
  }
}

class SpeciesInfoContent extends StatelessWidget {
  final SpeciesWithLocalImages species;
  final Language language;
  final EdgeInsetsGeometry padding;
  final bool scrollable;

  const SpeciesInfoContent({
    required this.species,
    required this.language,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.s20,
      AppSpacing.s24,
      AppSpacing.s20,
      AppSpacing.s20,
    ),
    this.scrollable = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scientificName = species.species.getBinomialName();
    final commonNames = _getCommonNames();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          commonNames.isNotEmpty ? commonNames.first : scientificName,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        AppSpacing.heightS8,
        Text(
          scientificName,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppSpacing.s20),
        DetailSectionCard(
          child: Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s16,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(
                AppSpacing.s16,
                0,
                AppSpacing.s16,
                AppSpacing.s12,
              ),
              initiallyExpanded: true,
              leading: Icon(
                Icons.translate,
                color: theme.colorScheme.primary,
                size: 20,
              ),
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
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    ]
                  : commonNames
                        .map((name) => DetailBulletRow(label: name))
                        .toList(),
            ),
          ),
        ),
        AppSpacing.heightS12,
        DetailSectionCard(
          child: Padding(
            padding: AppSpacing.cardPaddingAll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.account_tree_outlined,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
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
                    .where((row) => row.scientific.isNotEmpty)
                    .map(
                      (row) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                        child: DetailKeyValueRow(
                          label: row.label,
                          primary: row.scientific,
                          secondary: row.common,
                          italicPrimary: true,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );

    if (!scrollable) {
      return Padding(padding: padding, child: content);
    }

    return SingleChildScrollView(padding: padding, child: content);
  }

  List<String> _getCommonNames() {
    final rawNames =
        species.species.commonNames[language] ??
        species.species.commonNames[Language.en] ??
        '';
    if (rawNames.isEmpty) return [];

    return rawNames
        .split(';')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  List<({String label, String scientific, String? common})>
  _getClassificationRows(BuildContext context) {
    final classification = species.species.classification;
    return [
      (
        label: context.loc.classificationGenus,
        scientific: classification.genusScientificName,
        common: classification.genusCommonNames[language],
      ),
      (
        label: context.loc.classificationFamily,
        scientific: classification.familyScientificName,
        common: classification.familyCommonNames[language],
      ),
      (
        label: context.loc.classificationOrder,
        scientific: classification.orderScientificName,
        common: classification.orderCommonNames[language],
      ),
      (
        label: context.loc.classificationClass,
        scientific: classification.classScientificName,
        common: classification.classCommonNames[language],
      ),
      if (classification.superClass != null &&
          classification.superClass!.isNotEmpty)
        (
          label: context.loc.classificationSuperClass,
          scientific: classification.superClass!,
          common: null,
        ),
    ];
  }
}

class DetailSectionCard extends StatelessWidget {
  final Widget child;

  const DetailSectionCard({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
        ),
      ),
      child: child,
    );
  }
}

class DetailBulletRow extends StatelessWidget {
  final String label;

  const DetailBulletRow({required this.label, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(top: AppSpacing.s8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class DetailKeyValueRow extends StatelessWidget {
  final String label;
  final String primary;
  final String? secondary;
  final bool italicPrimary;

  const DetailKeyValueRow({
    required this.label,
    required this.primary,
    this.secondary,
    this.italicPrimary = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
                primary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: italicPrimary ? FontStyle.italic : null,
                ),
              ),
              if (secondary != null && secondary!.isNotEmpty)
                Text(
                  secondary!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
