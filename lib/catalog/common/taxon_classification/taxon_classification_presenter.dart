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
      for (final (type, rank, id, scientificName, commonNames)
          in <(
            ClassificationRowType,
            TaxonRank,
            String?,
            String,
            Map<Language, List<String>>,
          )>[
            (
              ClassificationRowType.genus,
              TaxonRank.genus,
              classification.genusId,
              classification.genusScientificName,
              classification.genusCommonNames,
            ),
            (
              ClassificationRowType.family,
              TaxonRank.family,
              classification.familyId,
              classification.familyScientificName,
              classification.familyCommonNames,
            ),
            (
              ClassificationRowType.order,
              TaxonRank.order,
              classification.orderId,
              classification.orderScientificName,
              classification.orderCommonNames,
            ),
            (
              ClassificationRowType.classType,
              TaxonRank.classRank,
              classification.classId,
              classification.classScientificName,
              classification.classCommonNames,
            ),
          ])
        ClassificationRowViewModel(
          type: type,
          id: id,
          scientificName: scientificName,
          // Whatever enrichment may hold under "Not assigned" names no taxon.
          commonName: classification.isPlaceholder(rank)
              ? null
              : _resolveLocalizedName(commonNames, language),
          isPlaceholder: classification.isPlaceholder(rank),
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
