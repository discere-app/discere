import 'package:discere/app/info/widgets/source_card.dart';
import 'package:discere/catalog/model/source.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The sources as cards — two columns once there is room for them, one
/// otherwise. Never scrolls itself; the page owns the scroll.
class SourcesGrid extends StatelessWidget {
  final List<Source> sources;
  final AppLocalizations loc;

  const SourcesGrid({required this.sources, required this.loc, super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isWide ? 2 : 1,
        mainAxisSpacing: AppSpacing.s32,
        crossAxisSpacing: AppSpacing.s32,
        childAspectRatio: isWide ? 1.0 : 0.8,
        mainAxisExtent: 350,
      ),
      itemCount: sources.length,
      itemBuilder: (context, index) =>
          SourceCard(source: sources[index], loc: loc),
    );
  }
}
