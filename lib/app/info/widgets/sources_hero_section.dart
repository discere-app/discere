import 'package:discere/app/info/sources_hero_palette.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Opening statement of the credits page: what the data is and where it
/// comes from, before any of the individual sources.
class SourcesHeroSection extends StatelessWidget {
  final AppLocalizations loc;

  const SourcesHeroSection({required this.loc, super.key});

  @override
  Widget build(BuildContext context) {
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
            color: SourcesHeroPalette.accent,
          ),
        ),
        AppSpacing.heightS16,
        Text(
          loc.sourcesHeroDescription,
          style: const TextStyle(
            fontSize: 18,
            height: 1.6,
            color: SourcesHeroPalette.mutedText,
          ),
        ),
      ],
    );
  }
}
