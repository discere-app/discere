import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

import '../../model/biology/classification.dart';
import '../../model/language.dart';

class SpeciesClassificationWidget extends StatelessWidget {
  final Classification classification;
  final Language selectedLanguage;

  const SpeciesClassificationWidget({
    super.key,
    required this.classification,
    required this.selectedLanguage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTaxonomyEntry(
            context.loc.classificationClass,
            classification.classScientificName,
            classification.classCommonNames,
            context),
        _buildTaxonomyEntry(
            context.loc.classificationOrder,
            classification.orderScientificName,
            classification.orderCommonNames,
            context),
        _buildTaxonomyEntry(
            context.loc.classificationFamily,
            classification.familyScientificName,
            classification.familyCommonNames,
            context),
        if (classification.subFamily != null)
          Padding(
            padding: AppSpacing.paddingS4Vertical,
            child: Text(
              '${context.loc.classificationSubFamily}: ${classification.subFamily}',
            ),
          ),
        _buildTaxonomyEntry(
            context.loc.classificationGenus,
            classification.genusScientificName,
            classification.genusCommonNames,
            context),
      ],
    );
  }

  Widget _buildTaxonomyEntry(String level, String scientificName,
      Map<Language, String> commonNames, BuildContext context) {
    return Padding(
      padding: AppSpacing.paddingS4Vertical,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$level: $scientificName'),
          if (commonNames.isNotEmpty) ...[
            Text(
              '${context.loc.commonName}:',
            ),
            _buildCommonName(commonNames, context),
          ]
        ],
      ),
    );
  }

  Widget _buildCommonName(
      Map<Language, String> commonNames, BuildContext context) {
    final commonName =
        commonNames[selectedLanguage] ?? commonNames[Language.en];
    return Text(commonName ?? context.loc.commonNotAvailable);
  }
}
