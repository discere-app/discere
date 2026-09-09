import 'package:discere/external/inaturalist/inat_taxon_detail_reader.dart';
import 'package:discere/external/inaturalist/inat_taxon_details.dart';
import 'package:discere/shared/util/logger.dart';

/// The two facts the app shows about a taxon beyond its names and photos: a
/// link to its Wikipedia article and its IUCN conservation status.
///
/// Both come out of the same taxon detail document, so this asks
/// [INatTaxonDetails] rather than the API — a taxon whose photos were already
/// fetched costs no extra request here.
class INatMetadataApi {
  static final _log = Logger.forType(INatMetadataApi);

  final INatTaxonDetails _taxonDetails;

  const INatMetadataApi({required INatTaxonDetails taxonDetails})
    : _taxonDetails = taxonDetails;

  Future<({String? wikipediaUrl, String? iucnStatus})?> fetchTaxonMetadata(
    int taxonId,
  ) async {
    try {
      final taxonDetailResult = await _taxonDetails.fetch(taxonId);
      if (taxonDetailResult.taxonDetail == null) return null;

      return (
        wikipediaUrl: wikipediaUrlOf(taxonDetailResult.taxonDetail),
        iucnStatus: iucnStatusOf(taxonDetailResult.taxonDetail),
      );
    } catch (e) {
      _log.warn('fetchTaxonMetadata failed for taxon=$taxonId: $e');
      return null;
    }
  }

  /// Extracts the taxon's Wikipedia URL, if iNaturalist has curated one.
}
