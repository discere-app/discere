import 'package:discere/shared/model/language.dart';

class Classification {
  final String genusScientificName;
  final Map<Language, String> genusCommonNames;
  final String? subFamily;
  final String familyScientificName;
  final Map<Language, String> familyCommonNames;
  final String orderScientificName;
  final Map<Language, String> orderCommonNames;
  final String classScientificName;
  final Map<Language, String> classCommonNames;
  final String? superClass;

  Classification(
    this.genusScientificName,
    this.genusCommonNames,
    this.subFamily,
    this.familyScientificName,
    this.familyCommonNames,
    this.orderScientificName,
    this.orderCommonNames,
    this.classScientificName,
    this.classCommonNames,
    this.superClass,
  );
}
