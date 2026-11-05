/// Why a species' reference image could not be downloaded, and its pictures
/// came from iNaturalist instead. Stored in
/// `enrichment_species_capability_state.fallback_reason` on the species'
/// `base` row, so the diagnostics page can tell which outages cost how many
/// reference images, and how many of those came back later.
enum BaseImageFallbackReason {
  /// The host could not be reached or was struggling (see
  /// `ImageHostUnreachable`). Retried, first briefly, then daily.
  hostUnavailable('hostUnavailable'),

  /// The host answered 403 to every request it got. Retried like
  /// [hostUnavailable]: a refusal is the host's decision, which it may
  /// revise, and says nothing about the image.
  hostBlocked('hostBlocked'),

  /// The host answered and has none of the species' images. Given up on at
  /// once: asking again returns the same answer, and a reference-DB update
  /// that changes the URLs makes the row stale, which resets it.
  imageMissing('imageMissing'),

  /// Something on this device failed — the file system, or an error nobody
  /// expected. Retried like [hostUnavailable], so a local hiccup does not
  /// silently cost the reference image for good.
  other('other');

  const BaseImageFallbackReason(this.wireName);

  /// The value stored in the `fallback_reason` column. Spelled out rather
  /// than derived from [name] so renaming a constant cannot silently change
  /// persisted data.
  final String wireName;

  static BaseImageFallbackReason fromWire(String wireName) => values.firstWhere(
    (reason) => reason.wireName == wireName,
    orElse: () => throw ArgumentError.value(
      wireName,
      'wireName',
      'Unknown base image fallback reason',
    ),
  );
}
