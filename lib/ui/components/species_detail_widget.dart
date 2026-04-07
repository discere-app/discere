import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

import '../../model/biology/species_with_local_images.dart';
import '../../model/language.dart';
import '../../theme/app_spacing.dart';
import 'flashcard_back_widget.dart';
import 'species_external_links.dart';
import 'species_media_carousel.dart';

class SpeciesDetailWidget extends StatelessWidget {
  final SpeciesWithLocalImages species;
  final Language language;
  final bool isRefreshingImages;

  const SpeciesDetailWidget({
    super.key,
    required this.species,
    required this.language,
    this.isRefreshingImages = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = species.species;
    final commonNames = _localizedCommonNames();
    final primaryName = commonNames.isNotEmpty
        ? commonNames.first
        : data.getBinomialName();

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
              if (data.isDeprecated) _DeprecatedBanner(species: species),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.s20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.72,
                      ),
                      theme.colorScheme.surfaceContainerLow,
                    ],
                  ),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s12,
                        vertical: AppSpacing.s8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(
                          alpha: 0.72,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        context.loc.classificationSpecies,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    Text(
                      primaryName,
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      data.getBinomialName(),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    Wrap(
                      spacing: AppSpacing.s8,
                      runSpacing: AppSpacing.s8,
                      children: [
                        _InfoPill(
                          label:
                              '${context.loc.classificationFamily}: ${data.classification.familyScientificName}',
                        ),
                        _InfoPill(
                          label:
                              '${context.loc.classificationOrder}: ${data.classification.orderScientificName}',
                        ),
                        _InfoPill(
                          label:
                              '${context.loc.classificationClass}: ${data.classification.classScientificName}',
                        ),
                      ],
                    ),
                  ],
                ),
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
                        child: _ImageRefreshIndicator(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s16),
              _ZooFactsPanel(species: species, language: language),
              const SizedBox(height: AppSpacing.s16),
              DetailSectionCard(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s8),
                  child: SpeciesInfoContent(
                    species: species,
                    language: language,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s12,
                      AppSpacing.s12,
                      AppSpacing.s12,
                      AppSpacing.s8,
                    ),
                    scrollable: false,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s20),
              SpeciesExternalLinks(species: species.species),
            ],
          ),
        );
      },
    );
  }

  List<String> _localizedCommonNames() {
    final rawNames =
        species.species.commonNames[language] ??
        species.species.commonNames[Language.en] ??
        '';

    return rawNames
        .split(';')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }
}

class _ImageRefreshIndicator extends StatelessWidget {
  const _ImageRefreshIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Text(
            context.loc.speciesDetailLoadingImages,
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeprecatedBanner extends StatelessWidget {
  final SpeciesWithLocalImages species;

  const _DeprecatedBanner({required this.species});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s16),
      child: Material(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s12,
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  context.loc.speciesDeprecatedBanner,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZooFactsPanel extends StatelessWidget {
  final SpeciesWithLocalImages species;
  final Language language;

  const _ZooFactsPanel({required this.species, required this.language});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = species.species;

    return DetailSectionCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.loc.speciesDetailFactsTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Wrap(
              spacing: AppSpacing.s12,
              runSpacing: AppSpacing.s12,
              children: [
                _FactCard(
                  label: context.loc.speciesSize,
                  value: _valueOrFallback(context, data.size),
                  icon: Icons.straighten_rounded,
                ),
                _FactCard(
                  label: context.loc.speciesDepth,
                  value: _valueOrFallback(context, data.depth),
                  icon: Icons.water_rounded,
                ),
                _FactCard(
                  label: context.loc.speciesDetailHabitat,
                  value: context.loc.speciesDetailDummyHabitatValue,
                  icon: Icons.landscape_rounded,
                  isDummy: true,
                ),
                _FactCard(
                  label: context.loc.speciesDetailActivity,
                  value: context.loc.speciesDetailDummyActivityValue,
                  icon: Icons.wb_sunny_outlined,
                  isDummy: true,
                ),
                _FactCard(
                  label: context.loc.speciesDetailConservation,
                  value: context.loc.speciesDetailDummyConservationValue,
                  icon: Icons.shield_outlined,
                  isDummy: true,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              context.loc.speciesDetailDummyNotice,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _valueOrFallback(BuildContext context, String? value) {
    if (value == null || value.trim().isEmpty) {
      return context.loc.commonNotAvailable;
    }
    return value;
  }
}

class _FactCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isDummy;

  const _FactCard({
    required this.label,
    required this.value,
    required this.icon,
    this.isDummy = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minWidth: 148, maxWidth: 220),
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDummy
              ? theme.colorScheme.secondary.withValues(alpha: 0.18)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (isDummy)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s8,
                    vertical: AppSpacing.s4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Dummy',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;

  const _InfoPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
