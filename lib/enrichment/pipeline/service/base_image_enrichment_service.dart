import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/pipeline/model/import_enrichment_summary.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/util/concurrency_utils.dart';

/// Downloads FishBase/SealifeBase reference images for species that don't
/// already have a local copy — the `base` capability in the producer-consumer
/// enrichment pipeline, driven by `BaseWorker`. The optional
/// `onSpeciesCompleted` hook fires per species once it reaches a terminal
/// outcome (image saved to disk, or nothing to download), mirroring the
/// sibling enrichment services; `BaseWorker` itself ignores it and reads the
/// returned [ImportEnrichmentSummary] instead.
class BaseImageEnrichmentService {
  static const _maxConcurrentFetches = 3;
  static const _referenceImagesDirectory = 'reference_images';

  final SpeciesRepository _speciesRepository;
  final ImageService _imageService;

  const BaseImageEnrichmentService(this._speciesRepository, this._imageService);

  Future<ImportEnrichmentSummary> downloadBaseImagesForSpecies(
    Set<String> speciesIds, {
    void Function(String speciesId)? onSpeciesCompleted,
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
        var downloadSucceeded = true;
        try {
          final picturesByUrl = _picturesByUrl(species.pictures);
          if (picturesByUrl.isNotEmpty) {
            final downloaded = await _imageService.downloadAndSaveUrlMap(
              picturesByUrl.keys.toSet(),
              storageDirectory: _referenceImagesDirectory,
            );
            downloadSucceeded = downloaded.isNotEmpty;
            if (downloadSucceeded) {
              speciesWithImages++;
              imageCount += picturesByUrl.length;
            }
          }
        } catch (_) {
          // Keep going so one broken species image set does not block the deck.
          downloadSucceeded = false;
        } finally {
          // Only mark the species terminal once its image actually landed on
          // disk — the flashcard UI reads the local file, not the resolved
          // URL. Otherwise a failed download silently completes the stage
          // and the species never gets retried.
          if (downloadSucceeded) {
            onSpeciesCompleted?.call(species.id);
          }
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
