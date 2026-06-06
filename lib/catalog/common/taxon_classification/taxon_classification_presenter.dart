import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/common/taxon_classification/classification_row_view_model.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/common_name_utils.dart';

class TaxonClassificationPresenter {
  const TaxonClassificationPresenter();

  List<ClassificationRowViewModel> present(
    Classification classification,
    Language language,
  ) {
    final rows = <ClassificationRowViewModel>[
      ClassificationRowViewModel(
        type: ClassificationRowType.genus,
        id: classification.genusId,
        scientificName: classification.genusScientificName,
        commonName: _resolveLocalizedName(
          classification.genusCommonNames,
          language,
        ),
      ),
      ClassificationRowViewModel(
        type: ClassificationRowType.family,
        id: classification.familyId,
        scientificName: classification.familyScientificName,
        commonName: _resolveLocalizedName(
          classification.familyCommonNames,
          language,
        ),
      ),
      ClassificationRowViewModel(
        type: ClassificationRowType.order,
        id: classification.orderId,
        scientificName: classification.orderScientificName,
        commonName: _resolveLocalizedName(
          classification.orderCommonNames,
          language,
        ),
      ),
      ClassificationRowViewModel(
        type: ClassificationRowType.classType,
        id: classification.classId,
        scientificName: classification.classScientificName,
        commonName: _resolveLocalizedName(
          classification.classCommonNames,
          language,
        ),
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
