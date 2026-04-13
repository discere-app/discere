import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/species_detail/species_detail_content.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SpeciesDetailPage extends StatelessWidget {
  final SpeciesWithLocalImages species;
  final List<String> deckNames;
  final bool isRefreshingImages;
  final Language? language;

  const SpeciesDetailPage({
    super.key,
    required this.species,
    this.deckNames = const [],
    this.isRefreshingImages = false,
    this.language,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(species.species.getBinomialName())),
      body: Consumer<LanguageService>(
        builder: (context, languageService, child) {
          final currentLanguage = language ?? languageService.getLanguage();
          return SpeciesDetailContent(
            species: species,
            language: currentLanguage,
            deckNames: deckNames,
            isRefreshingImages: isRefreshingImages,
          );
        },
      ),
    );
  }
}
