import 'package:discere/ui/components/species_common_names_widget.dart';
import 'package:flutter/material.dart';

import '../../model/biology/species_with_local_images.dart';
import '../../model/language.dart';
import 'classification_widget.dart';
import 'image_carousel.dart';

class SpeciesDetailWidget extends StatelessWidget {
  final SpeciesWithLocalImages species;
  final Language language;

  const SpeciesDetailWidget(
      {super.key, required this.species, required this.language});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            children: [
              ImageCarousel(
                  key: const Key('image'),
                  images: species.localImages,
                  constraints: constraints),
              const Padding(padding: EdgeInsets.all(8)),
              SpeciesCommonNamesWidget(commonNames: _getSpeciesCommonName()),
              SpeciesClassificationWidget(
                  classification: species.species.classification,
                  selectedLanguage: language)
            ],
          ));
    });
  }

  List<String> _getSpeciesCommonName() {
    String commonName = species.species.commonNames[language] ??
        species.species.commonNames[Language.en] ??
        '';
    return commonName.split(';');
  }
}
