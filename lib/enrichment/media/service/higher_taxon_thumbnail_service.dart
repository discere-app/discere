import 'package:discere/catalog/search/higher_taxon_thumbnail_port.dart';
import 'package:discere/enrichment/pipeline/service/higher_taxon_id_resolver.dart';
import 'package:discere/external/inaturalist/inat_photo_api.dart';
import 'package:discere/shared/util/logger.dart';

/// The thumbnail a list shows for a genus, family, order or class: an
/// iNaturalist photo of the taxon, and only of one whose id is already
/// known.
///
/// Whether an iNaturalist taxon is the one a higher rank's name stands for
/// is decided by [HigherTaxonIdResolver.resolve], which reads the ancestry
/// of species below it — something a list row has no species for. A known
/// id is the step of that rule a row can take on its own: the reference
/// DB's, or one enrichment found and cached. So nothing is searched and
/// nothing is stored here, and a taxon without a known id keeps its
/// placeholder.
class HigherTaxonThumbnailService implements HigherTaxonThumbnailPort {
  static final _log = Logger.forType(HigherTaxonThumbnailService);

  final HigherTaxonIdResolver _taxonIdResolver;
  final INatPhotoApi _iNatPhotos;

  const HigherTaxonThumbnailService({
    required HigherTaxonIdResolver taxonIdResolver,
    required INatPhotoApi iNatPhotos,
  }) : _taxonIdResolver = taxonIdResolver,
       _iNatPhotos = iNatPhotos;

  @override
  Future<String?> thumbnailUrl(String entityKey) async {
    try {
      final taxonId = await _taxonIdResolver.knownTaxonId(entityKey);
      if (taxonId == null) return null;
      return await _iNatPhotos.fetchThumbnailUrl(taxonId);
    } catch (e) {
      _log.warn('Thumbnail lookup failed for $entityKey: $e');
      return null;
    }
  }
}
