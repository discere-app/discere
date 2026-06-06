import 'package:discere/shared/model/language.dart';

class Classification {
  final String? genusId;
  final String genusScientificName;
  final Map<Language, List<String>> genusCommonNames;
  final String? subFamily;
  final String? familyId;
  final String familyScientificName;
  final Map<Language, List<String>> familyCommonNames;
  final String? orderId;
  final String orderScientificName;
  final Map<Language, List<String>> orderCommonNames;
  final String? classId;
  final String classScientificName;
  final Map<Language, List<String>> classCommonNames;
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
    this.superClass, {
    this.genusId,
    this.familyId,
    this.orderId,
    this.classId,
  });
}
