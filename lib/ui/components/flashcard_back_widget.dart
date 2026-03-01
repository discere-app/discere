
import 'package:discere/extensions/localization_extension.dart';
import 'package:discere/ui/components/species_common_names_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/biology/species_with_local_images.dart';
import '../../model/language.dart';
import '../../service/common/language_service.dart';

class FlashCardBack extends StatelessWidget {
  final SpeciesWithLocalImages speciesWithLocalImages;

  const FlashCardBack({
    required this.speciesWithLocalImages,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageService>(
      builder: (context, languageService, child) {
        final selectedLanguage = languageService.getLanguage();

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..rotateY(3.14),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SelectableText(
                  speciesWithLocalImages.species.getBinomialName(),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white24),
                const SizedBox(height: 16),
                SpeciesCommonNamesWidget(
                    commonNames: getSpeciesCommonName(selectedLanguage)),
                const SizedBox(height: 16),
                const Divider(color: Colors.white24),
                const SizedBox(height: 16),
                SelectableText(
                  getSpeciesAdditionalInfo(selectedLanguage, context),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.5,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<String> getSpeciesCommonName(Language selectedLanguage) {
    String commonName =
        speciesWithLocalImages.species.commonNames[selectedLanguage] ??
            speciesWithLocalImages.species.commonNames[Language.en] ??
            '';

    return commonName.split(';');
  }

  String getSpeciesAdditionalInfo(Language language, BuildContext context) {
    final classification = {
      context.loc.classificationGenus: speciesWithLocalImages
              .species.classification.genusCommonNames[language] ??
          speciesWithLocalImages.species.classification.classScientificName,
      context.loc.classificationFamily: speciesWithLocalImages
              .species.classification.familyCommonNames[language] ??
          speciesWithLocalImages.species.classification.familyScientificName,
      context.loc.classificationOrder: speciesWithLocalImages
              .species.classification.orderCommonNames[language] ??
          speciesWithLocalImages.species.classification.orderScientificName,
      context.loc.classificationClass: speciesWithLocalImages
          .species.classification.classCommonNames[language],
      context.loc.classificationSuperClass:
          speciesWithLocalImages.species.classification.superClass,
    };

    return classification.entries.map((entry) {
      final value = entry.value;
      return value != null && value.isNotEmpty
          ? '${entry.key}: $value'
          : '${entry.key}: ${context.loc.commonNotAvailable}';
    }).join(' -> ');
  }
}
