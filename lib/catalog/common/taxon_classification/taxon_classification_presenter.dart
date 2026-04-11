import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/common/taxon_classification/classification_row_view_model.dart';
import 'package:discere/shared/model/language.dart';

class TaxonClassificationPresenter {
  const TaxonClassificationPresenter();

  List<ClassificationRowViewModel> present(
    Classification classification,
    Language language,
  ) {
    final rows = <ClassificationRowViewModel>[
      ClassificationRowViewModel(
        type: ClassificationRowType.genus,
        scientificName: classification.genusScientificName,
        commonName: _resolveLocalizedName(
          classification.genusCommonNames,
          language,
        ),
      ),
      ClassificationRowViewModel(
        type: ClassificationRowType.family,
        scientificName: classification.familyScientificName,
        commonName: _resolveLocalizedName(
          classification.familyCommonNames,
          language,
        ),
      ),
      ClassificationRowViewModel(
        type: ClassificationRowType.order,
        scientificName: classification.orderScientificName,
        commonName: _resolveLocalizedName(
          classification.orderCommonNames,
          language,
        ),
      ),
      ClassificationRowViewModel(
        type: ClassificationRowType.classType,
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
    Map<Language, String> names,
    Language language,
  ) {
    final localized = names[language];
    if (localized != null && localized.trim().isNotEmpty) return localized;

    final english = names[Language.en];
    if (english != null && english.trim().isNotEmpty) return english;

    return null;
  }
}
