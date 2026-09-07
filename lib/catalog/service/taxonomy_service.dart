import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxonomy_detail.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';

/// Reads a taxon and what sits under it, for the taxonomy detail screens.
///
/// Exists so those pages depend on the catalog's service layer rather than
/// on raw SQL: the detail page and the species picker are the only callers,
/// and both are widgets that would otherwise need a real database to build.
class TaxonomyService {
  final TaxonomyRepository _repository;

  const TaxonomyService(this._repository);

  Future<TaxonomyDetail> getDetail(SearchResult result) =>
      _repository.getDetail(result);

  /// The rank one level down — genera under a family, species under a genus.
  Future<List<SearchResult>> getChildren(SearchResult parent) =>
      _repository.getChildren(parent);

  /// Every species below [taxon], however many levels down that is.
  Future<List<SearchResult>> getAllSpeciesUnder(SearchResult taxon) =>
      _repository.getAllSpeciesUnder(taxon);

  Future<List<String>> getAvailableRegions(Set<String> speciesIds) =>
      _repository.getAvailableRegions(speciesIds);

  Future<Map<String, List<String>>> getAbundanceRawValuesByRegion(
    Set<String> speciesIds,
    Set<String> regionKeys,
  ) => _repository.getAbundanceRawValuesByRegion(speciesIds, regionKeys);

  Future<Map<String, List<String>>> getAllAbundanceRawValues(
    Set<String> speciesIds,
  ) => _repository.getAllAbundanceRawValues(speciesIds);
}
