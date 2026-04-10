import 'package:discere/catalog/model/classification.dart';
import 'package:discere/shared/model/language.dart';
import '../view_data/classification_row_view_data.dart';

class SpeciesClassificationPresenter {
  const SpeciesClassificationPresenter();

  List<ClassificationRowViewData> present(
    Classification classification,
    Language language,
  ) {
    final rows = <ClassificationRowViewData>[
      ClassificationRowViewData(
        type: ClassificationRowType.genus,
        scientificName: classification.genusScientificName,
        commonName: _resolveLocalizedName(
          classification.genusCommonNames,
          language,
        ),
      ),
      ClassificationRowViewData(
        type: ClassificationRowType.family,
        scientificName: classification.familyScientificName,
        commonName: _resolveLocalizedName(
          classification.familyCommonNames,
          language,
        ),
      ),
      ClassificationRowViewData(
        type: ClassificationRowType.order,
        scientificName: classification.orderScientificName,
        commonName: _resolveLocalizedName(
          classification.orderCommonNames,
          language,
        ),
      ),
      ClassificationRowViewData(
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
        ClassificationRowViewData(
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
