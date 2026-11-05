import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/pipeline/model/base_image_download_result.dart';
import 'package:discere/enrichment/pipeline/model/base_image_fallback_reason.dart';
import 'package:discere/shared/service/image_download_outcome.dart';
import 'package:discere/shared/service/image_service.dart';

/// Downloads a species' FishBase/SealifeBase reference images that don't
/// already have a local copy — the `base` capability in the producer-consumer
/// enrichment pipeline, driven by `BaseWorker` — and folds how each URL
/// ended into one [BaseImageDownloadResult] for the species.
class BaseImageEnrichmentService {
  static const _referenceImagesDirectory = 'reference_images';

  final ImageService _imageService;

  const BaseImageEnrichmentService(this._imageService);

  /// A host in cooldown is skipped rather than waited for: during an outage
  /// every species of a batch would otherwise sit out the same cooldown in
  /// turn, only to fail the same way.
  Future<BaseImageDownloadResult> downloadReferenceImages(
    Species species,
  ) async {
    final outcomes = await _imageService.downloadAndSaveUrls(
      {for (final picture in species.pictures) ?picture.url},
      storageDirectory: _referenceImagesDirectory,
      skipIfHostCoolingDown: true,
    );
    return _resultOf(outcomes.values);
  }

  /// One image on disk is enough for the species. Otherwise a host problem
  /// outweighs a missing image, because a host that could not be asked might
  /// still have the image, while giving up on it cannot be undone by a
  /// retry: the reason is [BaseImageFallbackReason.hostBlocked] when every
  /// host problem was a refusal, else
  /// [BaseImageFallbackReason.hostUnavailable]. A local failure is retried
  /// like a host problem ([BaseImageFallbackReason.other]) rather than given
  /// up on silently. Only when every URL was answered without its image is
  /// the species [BaseImageFallbackReason.imageMissing].
  static BaseImageDownloadResult _resultOf(
    Iterable<ImageDownloadOutcome> outcomes,
  ) {
    if (outcomes.any((outcome) => outcome is ImageSaved)) {
      return const BaseImageSaved();
    }
    final hostProblems = outcomes.whereType<ImageHostProblem>().toList();
    if (hostProblems.isNotEmpty) {
      final allRefused = hostProblems.every(
        (problem) => problem is ImageHostRefused,
      );
      final reason = allRefused
          ? BaseImageFallbackReason.hostBlocked
          : BaseImageFallbackReason.hostUnavailable;
      return BaseImageFailed(reason, host: hostProblems.first.host);
    }
    if (outcomes.any((outcome) => outcome is ImageLocalFailure)) {
      return const BaseImageFailed(BaseImageFallbackReason.other);
    }
    final missing = outcomes.whereType<ImageNotFound>().firstOrNull;
    return BaseImageFailed(
      BaseImageFallbackReason.imageMissing,
      host: missing?.host,
    );
  }
}
