import '../../model/biology/species.dart';
import '../../model/language.dart';
import '../../model/ui/species_identity_view_data.dart';

class SpeciesIdentityPresenter {
  const SpeciesIdentityPresenter();

  SpeciesIdentityViewData present(Species species, Language language) {
    final scientificName = species.getBinomialName();
    final commonNames = _resolveCommonNames(species, language);

    return SpeciesIdentityViewData(
      primaryName: commonNames.isNotEmpty ? commonNames.first : scientificName,
      scientificName: scientificName,
      commonNames: commonNames,
    );
  }

  List<String> _resolveCommonNames(Species species, Language language) {
    final rawNames =
        species.commonNames[language] ?? species.commonNames[Language.en] ?? '';
    if (rawNames.isEmpty) return const [];

    final names = <String>[];
    final seen = <String>{};

    for (final rawName in rawNames.split(';')) {
      final trimmed = rawName.trim();
      if (trimmed.isEmpty) continue;
      final normalized = trimmed.toLowerCase();
      if (!seen.add(normalized)) continue;
      names.add(trimmed);
    }

    return names;
  }
}
