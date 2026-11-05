import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/base_image_fallback_reason.dart';

/// How many species last fell back to iNaturalist for [reason] at [host],
/// grouped by where their reference image stands now ([baseState]) — the
/// diagnostics page's answer to which outages cost how many reference
/// images, and how many of those arrived later after all
/// ([EnrichmentWorkState.done]).
///
/// [host] is null for [BaseImageFallbackReason.other], which is no host's
/// doing.
class BaseImageFallbackCount {
  final BaseImageFallbackReason reason;
  final String? host;
  final EnrichmentWorkState baseState;
  final int count;

  const BaseImageFallbackCount({
    required this.reason,
    required this.host,
    required this.baseState,
    required this.count,
  });
}
