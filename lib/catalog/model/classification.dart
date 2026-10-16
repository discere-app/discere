import 'package:discere/catalog/model/taxon_rank.dart';
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

  /// The ranks of this chain that are a source's rank placeholder ("Not
  /// assigned") rather than a taxon. Such a rank keeps its id, so it can be
  /// navigated to, but has no name worth showing or asking for.
  final Set<TaxonRank> placeholderRanks;

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
    this.placeholderRanks = const {},
  });

  bool isPlaceholder(TaxonRank rank) => placeholderRanks.contains(rank);
}
