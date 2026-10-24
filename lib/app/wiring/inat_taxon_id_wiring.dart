import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_rejection_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/catalog/repository/inat_allowed_ancestor_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/pipeline/service/higher_taxon_id_resolver.dart';
import 'package:discere/enrichment/pipeline/service/inat_taxon_resolver.dart';
import 'package:discere/external/inaturalist/inat_taxon_details.dart';
import 'package:discere/external/inaturalist/inat_taxon_id_resolver.dart';

/// Builds the two resolvers of an iNaturalist taxon id — for species and
/// for the ranks above — over the same reference data: the ETL's ids, its
/// rejections and the phyla and classes a search hit may sit under
/// (docs/enrichment.md, "Die iNat-Taxon-ID").
({INatTaxonResolver species, HigherTaxonIdResolver higherRanks})
buildINatTaxonIdResolvers({
  required SpeciesRepository speciesRepository,
  required ExternalIdRepository externalIdRepository,
  required ExternalIdCacheRepository externalIdCacheRepository,
  required INatTaxonDetails iNatTaxonDetails,
  required INatTaxonIdResolver iNatTaxonIds,
}) {
  final rejections = ExternalIdRejectionRepository();
  final allowedAncestors = INatAllowedAncestorRepository();
  final species = INatTaxonResolver(
    speciesRepository,
    externalIdRepository,
    externalIdCacheRepository,
    rejections,
    allowedAncestors,
    iNatTaxonIds,
  );
  return (
    species: species,
    higherRanks: HigherTaxonIdResolver(
      externalIdRepository,
      externalIdCacheRepository,
      rejections,
      allowedAncestors,
      species,
      iNatTaxonDetails,
      iNatTaxonIds,
    ),
  );
}
