import 'package:discere/catalog/common/taxon_classification/classification_row_view_model.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/common_name_utils.dart';

class TaxonClassificationPresenter {
  const TaxonClassificationPresenter();

  List<ClassificationRowViewModel> present(Species species, Language language) {
    final classification = species.classification;
    final rows = <ClassificationRowViewModel>[
      ClassificationRowViewModel(
        type: ClassificationRowType.species,
        id: species.id,
        scientificName: species.getBinomialName(),
        commonName: _resolveLocalizedName(species.commonNames, language),
      ),
      for (final (type, rank, commonNames)
          in <(ClassificationRowType, TaxonRank, Map<Language, List<String>>)>[
            (
              ClassificationRowType.genus,
              TaxonRank.genus,
              classification.genusCommonNames,
            ),
            (
              ClassificationRowType.family,
              TaxonRank.family,
              classification.familyCommonNames,
            ),
            (
              ClassificationRowType.order,
              TaxonRank.order,
              classification.orderCommonNames,
            ),
            (
              ClassificationRowType.classType,
              TaxonRank.classRank,
              classification.classCommonNames,
            ),
          ])
        ClassificationRowViewModel(
          type: type,
          id: classification.idAt(rank),
          scientificName: classification.scientificNameAt(rank),
          // Whatever enrichment may hold under "Not assigned" names no taxon.
          commonName: classification.isUnassigned(rank)
              ? null
              : _resolveLocalizedName(commonNames, language),
          isUnassigned: classification.isUnassigned(rank),
        ),
    ];

    if (classification.superClass != null &&
        classification.superClass!.isNotEmpty) {
      rows.add(
        ClassificationRowViewModel(
          type: ClassificationRowType.superClass,
          scientificName: classification.superClass!,
        ),
      );
    }

    return rows;
  }

  String? _resolveLocalizedName(
    Map<Language, List<String>> names,
    Language language,
  ) {
    final resolved = resolveCommonNames(names, language);
    return resolved.isNotEmpty ? resolved.first : null;
  }
}
