import 'package:discere/external/inaturalist/inat_api_client.dart';
import 'package:discere/external/inaturalist/inat_photo_licensing.dart';
import 'package:discere/external/inaturalist/inat_taxon_detail_reader.dart';
import 'package:discere/external/inaturalist/inat_taxon_details.dart';
import 'package:discere/external/inaturalist/inat_taxon_id_resolver.dart';
import 'package:discere/external/inaturalist/models/inat_photo.dart';
import 'package:discere/shared/util/background_json.dart';
import 'package:discere/shared/util/logger.dart';

/// Fetches usable photos for a taxon.
///
/// Two sources, in that order: the curated gallery on the taxon record, then
/// community observations. The gallery is small but reliable; observations
/// fill it up when it is not enough. Which of them may actually be shown is
/// [usablePhotosOf]'s business, not this one's.
class INatPhotoApi {
  static final _log = Logger.forType(INatPhotoApi);

  final INatApiClient _api;
  final INatTaxonIdResolver _taxonIds;
  final INatTaxonDetails _taxonDetails;

  const INatPhotoApi({
    required INatApiClient api,
    required INatTaxonIdResolver taxonIds,
    required INatTaxonDetails taxonDetails,
  }) : _api = api,
       _taxonIds = taxonIds,
       _taxonDetails = taxonDetails;

  static const Map<String, Object> _observationPhotoFieldsExpanded = {
    'observation_photos': {
      'photo': {
        'id': true,
        'url': true,
        'medium_url': true,
        'license_code': true,
        'attribution': true,
      },
    },
  };

  /// Fetches photos for a species by its full scientific name (e.g. "Amphiprion ocellaris").
  ///
  /// If [taxonId] is provided, it skips the search and fetches directly.
  /// Returns a record with the discovered taxonId, up to [maxPhotos] photos,
  /// the taxon's English Wikipedia URL, and its IUCN Red List status code
  /// (e.g. "vu") if iNaturalist has these on file — all piggyback on the
  /// taxon detail fetch already done for the curated gallery, no extra
  /// request.
  Future<
    ({
      int taxonId,
      List<INatPhoto> photos,
      String? wikipediaUrl,
      String? iucnStatus,
    })?
  >
  fetchPhotos(
    String scientificName, {
    int? taxonId,
    int maxPhotos = 10,
    bool allowTier3Fallback = false,
  }) async {
    try {
      final resolvedTaxonId = await _taxonIds.resolve(
        scientificName,
        taxonId: taxonId,
      );

      if (resolvedTaxonId == null) {
        _log.debug('could not resolve taxon for "$scientificName"');
        return null;
      }

      // Step 2: Fetch FULL taxon record to get the curated gallery.
      final taxonDetailResult = await _taxonDetails.fetch(resolvedTaxonId);
      final curatedPhotos = taxonDetailResult.taxonDetail != null
          ? usablePhotosOf(taxonDetailResult.taxonDetail!)
          : <INatPhoto>[];
      final wikipediaUrl = wikipediaUrlOf(taxonDetailResult.taxonDetail);
      final iucnStatus = iucnStatusOf(taxonDetailResult.taxonDetail);
      var retryableFailure = taxonDetailResult.retryableFailure;

      // Step 3: Fetch observations until we reach the requested photo count.
      List<INatPhoto> allPhotos = [...curatedPhotos];

      if (allPhotos.length < maxPhotos) {
        final observationResult = await _fetchObservationPhotos(
          resolvedTaxonId,
          qualityGrade: 'research',
          limit: maxPhotos - allPhotos.length,
        );
        retryableFailure =
            retryableFailure || observationResult.retryableFailure;
        final observationPhotos = observationResult.photos;

        final seenUrls = curatedPhotos.map((p) => p.url).toSet();

        for (final p in observationPhotos) {
          if (!seenUrls.contains(p.url)) {
            allPhotos.add(p);
            seenUrls.add(p.url);
          }
        }

        if (allowTier3Fallback && allPhotos.length < maxPhotos) {
          final anyQualityResult = await _fetchObservationPhotos(
            resolvedTaxonId,
            qualityGrade: null,
            limit: maxPhotos - allPhotos.length,
          );
          retryableFailure =
              retryableFailure || anyQualityResult.retryableFailure;
          final anyQualityPhotos = anyQualityResult.photos;

          for (final p in anyQualityPhotos) {
            if (!seenUrls.contains(p.url)) {
              allPhotos.add(p);
              seenUrls.add(p.url);
            }
          }
        }
      }

      if (allPhotos.length > maxPhotos) {
        allPhotos = allPhotos.take(maxPhotos).toList();
      }

      if (allPhotos.isEmpty && retryableFailure) {
        INatApiClient.logDebug(
          'iNat photo fetch deferred for "$scientificName" '
          '(taxon=$resolvedTaxonId, retryable failure)',
        );
        return null;
      }

      return (
        taxonId: resolvedTaxonId,
        photos: allPhotos,
        wikipediaUrl: wikipediaUrl,
        iucnStatus: iucnStatus,
      );
    } on TaxonNotFoundException {
      rethrow;
    } catch (e) {
      _log.warn('fetchPhotos failed for "$scientificName": $e');
      return null;
    }
  }

  /// Fetches just the taxon-detail-derived metadata (Wikipedia URL, IUCN
  /// status) for an already-known [taxonId] — no photo/observation calls.
  ///
  /// Intended for opportunistic backfill: species enriched before a field
  /// like `iucnStatus` existed have a cached taxon ID but never had that
  /// field fetched. This lets a caller top it up on demand with a single
  /// lightweight call instead of a full re-enrichment.
  /// Warms the taxon-detail cache for a whole batch at once. Kept on the
  /// service because its callers hold this, not [INatTaxonDetails] — that
  /// changes when the four API areas get their own types.
  Future<void> prefetchTaxonDetails(Iterable<int> taxonIds) =>
      _taxonDetails.prefetch(taxonIds);

  /// Fetches a single remote thumbnail URL for a taxon.
  ///
  /// This lightweight helper is intended for search-result thumbnails where we
  /// want to enrich the UI without downloading or persisting images locally.
  /// It resolves the taxon, loads the curated taxon detail, and returns the
  /// first available medium-sized photo URL when one exists.
  Future<String?> fetchThumbnailUrl(
    String scientificName, {
    int? taxonId,
  }) async {
    final stopwatch = Stopwatch()..start();
    INatApiClient.logDebug('iNat thumbnail start for "$scientificName"');
    try {
      final resolvedTaxonId = await _taxonIds.resolve(
        scientificName,
        taxonId: taxonId,
      );
      if (resolvedTaxonId == null) {
        INatApiClient.logDebug(
          'iNat thumbnail no taxon for "$scientificName" '
          '(${stopwatch.elapsedMilliseconds}ms)',
        );
        return null;
      }

      final taxonDetail = await _taxonDetails.fetch(resolvedTaxonId);
      if (taxonDetail.taxonDetail == null) {
        INatApiClient.logDebug(
          'iNat thumbnail no taxon detail for "$scientificName" '
          '(taxon=$resolvedTaxonId, ${stopwatch.elapsedMilliseconds}ms)',
        );
        return null;
      }

      final photos = usablePhotosOf(taxonDetail.taxonDetail!);
      if (photos.isEmpty) {
        INatApiClient.logDebug(
          'iNat thumbnail no photos for "$scientificName" '
          '(taxon=$resolvedTaxonId, ${stopwatch.elapsedMilliseconds}ms)',
        );
        return null;
      }

      INatApiClient.logDebug(
        'iNat thumbnail resolved for "$scientificName" '
        '(taxon=$resolvedTaxonId, ${stopwatch.elapsedMilliseconds}ms)',
      );
      return photos.first.mediumUrl;
    } catch (e) {
      INatApiClient.logDebug(
        'iNat thumbnail fetch error for "$scientificName" '
        '(${stopwatch.elapsedMilliseconds}ms): $e',
      );
      return null;
    }
  }

  /// Fetches photos from the top observations for a taxon.
  /// Strictly filters for CC licensing as per legal safety requirements.
  Future<({List<INatPhoto> photos, bool retryableFailure})>
  _fetchObservationPhotos(
    int taxonId, {
    String? qualityGrade = 'research',
    int limit = 10,
  }) async {
    try {
      final uri = _api.uri(
        '/observations',
        queryParameters: {
          'photos': 'true',
          'photo_licensed': 'true', // Only licensed (CC) images
          'per_page': '50', // Search pool for filtering
          'order_by': 'votes', // Prioritize popular/beautiful shots
        },
        queryParametersAll: {
          'taxon_id': [taxonId.toString()],
          if (qualityGrade != null) 'quality_grade': [qualityGrade],
        },
      );

      final response = await _api.get(
        uri,
        fields: _observationPhotoFieldsExpanded,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return (
          photos: const <INatPhoto>[],
          retryableFailure: INatApiClient.isRetryableStatus(response.statusCode),
        );
      }

      final data = Map<String, dynamic>.from(
        ((await BackgroundJson.decodeBytes(response.bodyBytes)) as Map)
            .cast<Object?, Object?>(),
      );
      final results = data['results'] as List<dynamic>?;
      if (results == null) {
        return (photos: const <INatPhoto>[], retryableFailure: false);
      }

      final photos = <INatPhoto>[];
      for (final obs in results) {
        final obsPhotos = obs['observation_photos'] as List<dynamic>?;
        if (obsPhotos == null) continue;

        for (final op in obsPhotos) {
          final photo = op['photo'] as Map<String, dynamic>?;
          if (photo == null) continue;

          final inatPhoto = parsePhoto(photo);
          if (inatPhoto != null) {
            photos.add(inatPhoto);
          }

          if (photos.length >= limit) break;
        }
        if (photos.length >= limit) break;
      }
      return (photos: photos, retryableFailure: false);
    } catch (e) {
      _log.warn('fetchObservationPhotos failed (taxon=$taxonId): $e');
      return (photos: const <INatPhoto>[], retryableFailure: true);
    }
  }
}
