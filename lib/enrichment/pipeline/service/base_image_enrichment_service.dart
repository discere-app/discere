import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/pipeline/model/import_enrichment_summary.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/util/concurrency_utils.dart';

/// Downloads FishBase/SealifeBase reference images for species that don't
/// already have a local copy — the `base` capability in the producer-consumer
/// enrichment pipeline, driven by `BaseWorker`. Reports how many species got
/// an image actually saved to disk (and the total image count) through the
/// returned [ImportEnrichmentSummary]; `BaseWorker` marks a species terminal
/// only when that count is non-zero, so a species whose download silently
/// failed stays pending for retry rather than completing without a local file.
class BaseImageEnrichmentService {
  static const _maxConcurrentFetches = 3;
  static const _referenceImagesDirectory = 'reference_images';

  final SpeciesRepository _speciesRepository;
  final ImageService _imageService;

  const BaseImageEnrichmentService(this._speciesRepository, this._imageService);

  Future<ImportEnrichmentSummary> downloadBaseImagesForSpecies(
    Set<String> speciesIds, {
    bool Function()? isCancelled,
  }) async {
    if (speciesIds.isEmpty) {
      return ImportEnrichmentSummary.empty;
    }

    final speciesList = (await _speciesRepository.getSpecies(
      speciesIds,
    )).toList();
    var speciesWithImages = 0;
    var imageCount = 0;

    await runConcurrently<Species>(
      speciesList,
      maxConcurrent: _maxConcurrentFetches,
      isCancelled: isCancelled,
      task: (species) async {
        try {
          final picturesByUrl = _picturesByUrl(species.pictures);
          if (picturesByUrl.isNotEmpty) {
            final downloaded = await _imageService.downloadAndSaveUrlMap(
              picturesByUrl.keys.toSet(),
              storageDirectory: _referenceImagesDirectory,
            );
            if (downloaded.isNotEmpty) {
              speciesWithImages++;
              imageCount += picturesByUrl.length;
            }
          }
        } catch (_) {
          // Keep going so one broken species image set does not block the deck.
        }
      },
    );

    return ImportEnrichmentSummary(
      imageSpeciesCount: speciesWithImages,
      imageCount: imageCount,
      commonNameSpeciesCount: 0,
      commonNameCount: 0,
    );
  }

  Map<String, Picture> _picturesByUrl(Iterable<Picture> pictures) {
    final picturesByUrl = <String, Picture>{};
    for (final picture in pictures) {
      final url = picture.url;
      if (url == null || url.isEmpty) continue;
      picturesByUrl.putIfAbsent(url, () => picture);
    }
    return picturesByUrl;
  }
}
