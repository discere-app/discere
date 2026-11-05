import 'package:discere/enrichment/pipeline/model/base_image_fallback_reason.dart';

/// How downloading one species' reference images ended, as
/// `BaseImageEnrichmentService` folds its per-URL outcomes together for
/// `BaseWorker`.
sealed class BaseImageDownloadResult {
  const BaseImageDownloadResult();
}

/// At least one of the species' reference images is on disk.
final class BaseImageSaved extends BaseImageDownloadResult {
  const BaseImageSaved();
}

/// None of the species' reference images could be saved, for [reason]. [host]
/// is the host the reason concerns — the one with the problem, or the one
/// that answered without the image — and null for
/// [BaseImageFallbackReason.other], which is no host's doing.
final class BaseImageFailed extends BaseImageDownloadResult {
  final BaseImageFallbackReason reason;
  final String? host;

  const BaseImageFailed(this.reason, {this.host});
}
