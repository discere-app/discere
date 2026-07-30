import 'dart:async';

import 'package:discere/shared/service/image_service.dart';
import 'package:http/http.dart' as http;

/// Whether a stage failure should be retried ([temporary]) or surfaced as a
/// terminal failure right away ([permanent]).
enum EnrichmentFailureKind { temporary, permanent }

/// Classifies a stage failure so the job executor knows whether to retry the
/// stage or mark it permanently failed. Network-level failures (timeouts,
/// dropped connections) are temporary by default; anything else — including
/// a non-retryable [HttpDownloadException] — is treated as permanent.
EnrichmentFailureKind classifyEnrichmentFailure(Object error) {
  if (error is TimeoutException) return EnrichmentFailureKind.temporary;
  if (error is http.ClientException) return EnrichmentFailureKind.temporary;
  if (error is HttpDownloadException) {
    return error.isRetryable
        ? EnrichmentFailureKind.temporary
        : EnrichmentFailureKind.permanent;
  }
  return EnrichmentFailureKind.permanent;
}
