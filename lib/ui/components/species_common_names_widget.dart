import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import 'detail_content_widgets.dart';

class SpeciesCommonNamesSection extends StatelessWidget {
  final List<String> commonNames;
  final bool initiallyExpanded;

  const SpeciesCommonNamesSection({
    super.key,
    required this.commonNames,
    this.initiallyExpanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DetailSectionCard(
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            0,
            AppSpacing.s16,
            AppSpacing.s12,
          ),
          initiallyExpanded: initiallyExpanded,
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
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ]
              : commonNames
                    .map((name) => DetailBulletRow(label: name))
                    .toList(),
        ),
      ),
    );
  }
}
