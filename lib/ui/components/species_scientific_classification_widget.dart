import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

import '../../model/ui/classification_row_view_data.dart';
import '../../theme/app_spacing.dart';
import 'detail_content_widgets.dart';

class SpeciesScientificClassificationSection extends StatelessWidget {
  final List<ClassificationRowViewData> rows;

  const SpeciesScientificClassificationSection({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DetailSectionCard(
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
            ...rows
                .where((row) => row.scientificName.isNotEmpty)
                .map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                    child: DetailKeyValueRow(
                      label: _label(context, row.type),
                      primary: row.scientificName,
                      secondary: row.commonName,
                      italicPrimary: true,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _label(BuildContext context, ClassificationRowType type) {
    switch (type) {
      case ClassificationRowType.genus:
        return context.loc.classificationGenus;
      case ClassificationRowType.family:
        return context.loc.classificationFamily;
      case ClassificationRowType.order:
        return context.loc.classificationOrder;
      case ClassificationRowType.classType:
        return context.loc.classificationClass;
      case ClassificationRowType.superClass:
        return context.loc.classificationSuperClass;
    }
  }
}
