import 'dart:convert';
import 'package:discere/shared/util/logger.dart';
import 'package:http/http.dart' as http;
import './models/inat_photo.dart';
import './models/inat_common_name.dart';
import 'package:discere/shared/util/background_json.dart';

/// Small gateway for Discere's iNaturalist integration.
///
/// The service resolves iNaturalist taxon IDs by scientific name and then
/// exposes two capabilities used during post-import enrichment:
/// fetching legally usable photos and fetching ranked multilingual common
/// names for supported app languages.
class INaturalistService {
  static final _log = Logger.forType(INaturalistService);
  static const bool _enableINatDebugLogging = true;
  static const _apiHost = 'api.inaturalist.org';
  static const _legacyWebHost = 'www.inaturalist.org';
  static const _apiBasePath = '/v2';
  static const _taxonDetailBatchSize = 30;
  final http.Client _client;
  final Map<String, int> _resolvedTaxonIdMemo = <String, int>{};
  final Map<String, Future<int?>> _inFlightTaxonIdMemo =
      <String, Future<int?>>{};
  final Map<int, Map<String, dynamic>> _taxonDetailMemo =
      <int, Map<String, dynamic>>{};
  final Map<
    int,
    Future<({Map<String, dynamic>? taxonDetail, bool retryableFailure})>
  >
  _inFlightTaxonDetailMemo =
      <
        int,
        Future<({Map<String, dynamic>? taxonDetail, bool retryableFailure})>
      >{};

  INaturalistService({http.Client? client}) : _client = client ?? http.Client();

  static const _userAgent =
      'DiscereApp/1.1 (ch.feberle.discere; https://github.com/feberle/discere)';

  static const Map<String, String> _supportedLexicons = {
    'english': 'en',
    'german': 'de',
    'french': 'fr',
    'spanish': 'es',
  };

  static const _taxonSearchFields =
      'id,name,rank,preferred_common_name,matched_term';
  static const Map<String, Object> _taxonSearchFieldsExpanded = {
    'id': true,
    'name': true,
    'rank': true,
    'preferred_common_name': true,
    'matched_term': true,
    'iconic_taxon_name': true,
    'default_photo': {
      'id': true,
      'url': true,
      'medium_url': true,
      'license_code': true,
    },
  };
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

  static const Map<String, Object> _taxonDetailFieldsExpanded = {
    'id': true,
    'name': true,
    'rank': true,
    'preferred_common_name': true,
    'iconic_taxon_name': true,
    'wikipedia_url': true,
    'wikipedia_summary': true,
    'default_photo': {
      'id': true,
      'url': true,
      'medium_url': true,
      'license_code': true,
      'attribution': true,
    },
    'taxon_photos': {
      'photo': {
        'id': true,
        'url': true,
        'medium_url': true,
        'license_code': true,
        'attribution': true,
      },
    },
  };

  /// All CC license codes that are allowed for non-commercial use.
  static const _allowedLicenses = {
    'cc-by',
    'cc-by-sa',
    'cc-by-nc',
    'cc-by-nd',
    'cc-by-nc-sa',
    'cc-by-nc-nd',
    'cc0',
    'pd', // Public Domain (sometimes used instead of cc0)
  };

  /// Searches iNaturalist taxa by a free-text query (scientific or common name).
  ///
  /// Returns up to [perPage] active candidates across the taxonomic ranks that
  /// Discere can surface in search. Each entry contains the scientific name,
  /// the iNat taxon ID, the taxon rank, and the preferred common name if
  /// available. Returns an empty list on network errors or timeouts so callers
  /// can treat this as a best-effort supplement.
  Future<List<Map<String, dynamic>>> searchTaxa(
    String query, {
    int perPage = 20,
  }) async {
    try {
      final uri = _buildApiUri(
        '/taxa',
        queryParameters: {
          'q': query.trim(),
          'per_page': perPage.toString(),
          'is_active': 'true',
        },
        queryParametersAll: {
          'rank': const [
            'class',
            'order',
            'family',
            'genus',
            'species',
            'subspecies',
          ],
        },
      );

      final response = await _executeGet(
        uri,
        fields: _taxonSearchFieldsExpanded,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return const [];

      final data = Map<String, dynamic>.from(
        ((await BackgroundJson.decodeBytes(response.bodyBytes)) as Map)
            .cast<Object?, Object?>(),
      );
      final results = data['results'] as List<dynamic>?;
      if (results == null) return const [];

      return results.whereType<Map<String, dynamic>>().map((r) {
        final defaultPhoto = r['default_photo'] as Map<String, dynamic>?;
        return <String, dynamic>{
          'id': r['id'] as int?,
          'scientific_name': r['name'] as String? ?? '',
          'rank': r['rank'] as String? ?? '',
          'preferred_common_name': r['preferred_common_name'] as String?,
          'matched_term': r['matched_term'] as String?,
          'iconic_taxon_name': r['iconic_taxon_name'] as String?,
          'default_photo_url': defaultPhoto?['url'] as String?,
          'default_photo_medium_url': defaultPhoto?['medium_url'] as String?,
          'default_photo_license_code':
              defaultPhoto?['license_code'] as String?,
        };
      }).toList();
    } catch (e) {
      _log.warn('searchTaxa failed for "$query": $e');
      return const [];
    }
  }

  /// Fetches photos for a species by its full scientific name (e.g. "Amphiprion ocellaris").
  ///
  /// If [taxonId] is provided, it skips the search and fetches directly.
  /// Returns a record with the discovered taxonId and up to [maxPhotos] photos.
  Future<({int taxonId, List<INatPhoto> photos})?> fetchPhotos(
    String scientificName, {
    int? taxonId,
    int maxPhotos = 10,
    bool allowTier3Fallback = false,
  }) async {
    try {
      final resolvedTaxonId = await _resolveTaxonId(
        scientificName,
        taxonId: taxonId,
      );

      if (resolvedTaxonId == null) {
        _log.debug('could not resolve taxon for "$scientificName"');
        return null;
      }

      // Step 2: Fetch FULL taxon record to get the curated gallery.
      final taxonDetailResult = await _fetchTaxonDetail(resolvedTaxonId);
      final curatedPhotos = taxonDetailResult.taxonDetail != null
          ? _extractTaxonPhotos(taxonDetailResult.taxonDetail!)
          : <INatPhoto>[];
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
        _logDebug(
          'iNat photo fetch deferred for "$scientificName" '
          '(taxon=$resolvedTaxonId, retryable failure)',
        );
        return null;
      }

      return (taxonId: resolvedTaxonId, photos: allPhotos);
    } catch (e) {
      _log.warn('fetchPhotos failed for "$scientificName": $e');
      return null;
    }
  }

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
    _logDebug('iNat thumbnail start for "$scientificName"');
    try {
      final resolvedTaxonId = await _resolveTaxonId(
        scientificName,
        taxonId: taxonId,
      );
      if (resolvedTaxonId == null) {
        _logDebug(
          'iNat thumbnail no taxon for "$scientificName" '
          '(${stopwatch.elapsedMilliseconds}ms)',
        );
        return null;
      }

      final taxonDetail = await _fetchTaxonDetail(resolvedTaxonId);
      if (taxonDetail.taxonDetail == null) {
        _logDebug(
          'iNat thumbnail no taxon detail for "$scientificName" '
          '(taxon=$resolvedTaxonId, ${stopwatch.elapsedMilliseconds}ms)',
        );
        return null;
      }

      final photos = _extractTaxonPhotos(taxonDetail.taxonDetail!);
      if (photos.isEmpty) {
        _logDebug(
          'iNat thumbnail no photos for "$scientificName" '
          '(taxon=$resolvedTaxonId, ${stopwatch.elapsedMilliseconds}ms)',
        );
        return null;
      }

      _logDebug(
        'iNat thumbnail resolved for "$scientificName" '
        '(taxon=$resolvedTaxonId, ${stopwatch.elapsedMilliseconds}ms)',
      );
      return photos.first.mediumUrl;
    } catch (e) {
      _logDebug(
        'iNat thumbnail fetch error for "$scientificName" '
        '(${stopwatch.elapsedMilliseconds}ms): $e',
      );
      return null;
    }
  }

  Future<void> prefetchTaxonDetails(Iterable<int> taxonIds) async {
    final uniqueTaxonIds = taxonIds.toSet().toList()..sort();
    final missingTaxonIds = uniqueTaxonIds
        .where((taxonId) => !_taxonDetailMemo.containsKey(taxonId))
        .toList(growable: false);
    if (missingTaxonIds.isEmpty) return;

    for (final chunk in _chunked(missingTaxonIds, _taxonDetailBatchSize)) {
      try {
        final detailsById = await _fetchTaxonDetailsBatch(chunk);
        _taxonDetailMemo.addAll(detailsById);
      } catch (e) {
        _logDebug('iNat taxon detail prefetch failed for $chunk: $e');
      }
    }
  }

  /// Fetches ranked common names for a taxon.
  ///
  /// Supports species and higher taxonomy ranks. The returned map is keyed by
  /// app language code (`de`, `en`, `fr`, `es`) and values are ordered from
  /// best to worst candidate according to iNaturalist ranking metadata.
  Future<({int taxonId, Map<String, List<INatCommonName>> commonNames})?>
  fetchCommonNames(String scientificName, {int? taxonId, String? rank}) async {
    try {
      final resolvedTaxonId = await _resolveTaxonId(
        scientificName,
        taxonId: taxonId,
        rank: rank,
      );
      if (resolvedTaxonId == null) return null;

      final uri = Uri.https(_legacyWebHost, '/taxon_names.json', {
        'taxon_id': resolvedTaxonId.toString(),
        'per_page': '200',
      });
      final response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final decoded = await BackgroundJson.decodeBytes(response.bodyBytes);
      final rows = _extractTaxonNameRows(decoded);
      final namesByLanguage = <String, List<INatCommonName>>{};

      for (final row in rows) {
        final commonName = _parseCommonName(row);
        if (commonName == null) continue;
        namesByLanguage
            .putIfAbsent(commonName.languageCode, () => [])
            .add(commonName);
      }

      final result = <String, List<INatCommonName>>{};
      for (final entry in namesByLanguage.entries) {
        final ranked = _rankCommonNames(entry.value);
        if (ranked.isNotEmpty) result[entry.key] = ranked;
      }

      return (taxonId: resolvedTaxonId, commonNames: result);
    } catch (e) {
      _log.warn('fetchCommonNames failed for "$scientificName": $e');
      return null;
    }
  }

  /// Fetches a single taxon record by ID to retrieve the curated gallery.
  Future<({Map<String, dynamic>? taxonDetail, bool retryableFailure})>
  _fetchTaxonDetail(int taxonId) async {
    final cachedTaxonDetail = _taxonDetailMemo[taxonId];
    if (cachedTaxonDetail != null) {
      return (taxonDetail: cachedTaxonDetail, retryableFailure: false);
    }

    final inFlight = _inFlightTaxonDetailMemo[taxonId];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _fetchTaxonDetailUncached(taxonId);
    _inFlightTaxonDetailMemo[taxonId] = future;
    try {
      final result = await future;
      final taxonDetail = result.taxonDetail;
      if (taxonDetail != null) {
        _taxonDetailMemo[taxonId] = taxonDetail;
      }
      return result;
    } finally {
      _inFlightTaxonDetailMemo.remove(taxonId);
    }
  }

  Future<({Map<String, dynamic>? taxonDetail, bool retryableFailure})>
  _fetchTaxonDetailUncached(int taxonId) async {
    final stopwatch = Stopwatch()..start();
    try {
      final uri = _buildApiUri('/taxa/$taxonId');
      final response = await _executeGet(
        uri,
        fields: _taxonDetailFieldsExpanded,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _logDebug(
          'iNat taxon detail failed (taxon=$taxonId, '
          'status=${response.statusCode}, ${stopwatch.elapsedMilliseconds}ms)',
        );
        return (
          taxonDetail: null,
          retryableFailure: _isRetryableStatus(response.statusCode),
        );
      }

      final data = Map<String, dynamic>.from(
        ((await BackgroundJson.decodeBytes(response.bodyBytes)) as Map)
            .cast<Object?, Object?>(),
      );
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) {
        _logDebug(
          'iNat taxon detail empty (taxon=$taxonId, '
          '${stopwatch.elapsedMilliseconds}ms)',
        );
        return (taxonDetail: null, retryableFailure: false);
      }

      _logDebug(
        'iNat taxon detail ok (taxon=$taxonId, '
        '${stopwatch.elapsedMilliseconds}ms)',
      );
      return (
        taxonDetail: results.first as Map<String, dynamic>,
        retryableFailure: false,
      );
    } catch (e) {
      _logDebug(
        'iNat taxon detail error (taxon=$taxonId, '
        '${stopwatch.elapsedMilliseconds}ms): $e',
      );
      return (taxonDetail: null, retryableFailure: true);
    }
  }

  Future<Map<int, Map<String, dynamic>>> _fetchTaxonDetailsBatch(
    List<int> taxonIds,
  ) async {
    if (taxonIds.isEmpty) return const <int, Map<String, dynamic>>{};

    final sortedTaxonIds = [...taxonIds]..sort();
    final path = '/taxa/${sortedTaxonIds.join(',')}';
    final uri = _buildApiUri(path);
    final response = await _executeGet(
      uri,
      fields: _taxonDetailFieldsExpanded,
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Batch taxon detail request failed with status ${response.statusCode}',
        uri,
      );
    }

    final data = Map<String, dynamic>.from(
      ((await BackgroundJson.decodeBytes(response.bodyBytes)) as Map)
          .cast<Object?, Object?>(),
    );
    final results = data['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) {
      return const <int, Map<String, dynamic>>{};
    }

    final detailsById = <int, Map<String, dynamic>>{};
    for (final row in results.whereType<Map<String, dynamic>>()) {
      final id = row['id'] as int?;
      if (id == null) continue;
      detailsById[id] = row;
    }
    _logDebug(
      'iNat taxon detail batch ok '
      '(requested=${sortedTaxonIds.length}, received=${detailsById.length})',
    );
    return detailsById;
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
      final uri = _buildApiUri(
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

      final response = await _executeGet(
        uri,
        fields: _observationPhotoFieldsExpanded,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return (
          photos: const <INatPhoto>[],
          retryableFailure: _isRetryableStatus(response.statusCode),
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

          final inatPhoto = _parsePhoto(photo);
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

  /// Checks if the API result is a relevant match for the query.
  bool _isRelevantMatch(String query, String result) {
    return result.toLowerCase().trim() == query.toLowerCase().trim();
  }

  bool _isRetryableStatus(int statusCode) {
    return statusCode == 429 || statusCode >= 500;
  }

  /// Resolves an iNaturalist taxon ID from a scientific name and optional rank.
  Future<int?> _resolveTaxonId(
    String scientificName, {
    int? taxonId,
    String? rank,
  }) async {
    if (taxonId != null) return taxonId;
    final memoKey = _taxonResolveMemoKey(scientificName, rank: rank);
    final cachedTaxonId = _resolvedTaxonIdMemo[memoKey];
    if (cachedTaxonId != null) {
      _logDebug(
        'iNat resolve taxon memo hit "$scientificName" -> $cachedTaxonId',
      );
      return cachedTaxonId;
    }
    final inFlight = _inFlightTaxonIdMemo[memoKey];
    if (inFlight != null) {
      _logDebug('iNat resolve taxon join "$scientificName"');
      return inFlight;
    }

    final future = _resolveTaxonIdUncached(scientificName, rank: rank);
    _inFlightTaxonIdMemo[memoKey] = future;
    try {
      final resolvedTaxonId = await future;
      if (resolvedTaxonId != null) {
        _resolvedTaxonIdMemo[memoKey] = resolvedTaxonId;
      }
      return resolvedTaxonId;
    } finally {
      _inFlightTaxonIdMemo.remove(memoKey);
    }
  }

  Future<int?> _resolveTaxonIdUncached(
    String scientificName, {
    String? rank,
  }) async {
    final stopwatch = Stopwatch()..start();
    final normalizedRank = (rank != null && rank.trim().isNotEmpty)
        ? rank.trim()
        : 'species';

    final searchUri = _buildApiUri(
      '/taxa',
      queryParameters: {
        'q': scientificName.trim(),
        'per_page': '10',
        'fields': _taxonSearchFields,
      },
      queryParametersAll: {
        'rank': [normalizedRank],
      },
    );

    final searchResponse = await _client
        .get(searchUri, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 10));

    if (searchResponse.statusCode != 200) {
      _logDebug(
        'iNat resolve taxon failed for "$scientificName" '
        '(status=${searchResponse.statusCode}, '
        '${stopwatch.elapsedMilliseconds}ms)',
      );
      return null;
    }

    final searchData = jsonDecode(searchResponse.body) as Map<String, dynamic>;
    final results = searchData['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) {
      _logDebug(
        'iNat resolve taxon empty for "$scientificName" '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
      return null;
    }

    for (final r in results) {
      final name = r['name'] as String? ?? '';
      final matchedTerm = r['matched_term'] as String?;

      if (_isRelevantMatch(scientificName, name) ||
          (matchedTerm != null &&
              _isRelevantMatch(scientificName, matchedTerm))) {
        final resolvedId = r['id'] as int?;
        _logDebug(
          'iNat resolve taxon matched "$scientificName" -> $resolvedId '
          '(${stopwatch.elapsedMilliseconds}ms)',
        );
        return resolvedId;
      }
    }

    final fallbackId = results.first['id'] as int?;
    _logDebug(
      'iNat resolve taxon fallback "$scientificName" -> $fallbackId '
      '(${stopwatch.elapsedMilliseconds}ms)',
    );
    return fallbackId;
  }

  String _taxonResolveMemoKey(String scientificName, {String? rank}) {
    final normalizedRank = (rank?.trim().toLowerCase().isNotEmpty ?? false)
        ? rank!.trim().toLowerCase()
        : 'species';
    final normalizedName = scientificName.trim().toLowerCase();
    return '$normalizedRank:$normalizedName';
  }

  /// Extracts curated photos from a taxon response.
  List<INatPhoto> _extractTaxonPhotos(Map<String, dynamic> taxon) {
    final photos = <INatPhoto>[];

    // Check taxon_photos array (expert-picked curated photos).
    final taxonPhotos = taxon['taxon_photos'] as List<dynamic>?;
    if (taxonPhotos != null) {
      for (final tp in taxonPhotos) {
        final photo = tp['photo'] as Map<String, dynamic>?;
        if (photo == null) continue;

        final inatPhoto = _parsePhoto(photo);
        if (inatPhoto != null) photos.add(inatPhoto);
      }
    }

    // Secondary Fallback: use default_photo if no taxon_photos were found.
    if (photos.isEmpty) {
      final defaultPhoto = taxon['default_photo'] as Map<String, dynamic>?;
      if (defaultPhoto != null) {
        final inatPhoto = _parsePhoto(defaultPhoto);
        if (inatPhoto != null) photos.add(inatPhoto);
      }
    }

    return photos;
  }

  /// Parses a single photo object from the API response.
  /// Returns null if the photo has no usable CC license or URL.
  INatPhoto? _parsePhoto(Map<String, dynamic> photo) {
    final url = photo['url'] as String?;
    if (url == null || url.isEmpty) return null;

    final licenseCode = (photo['license_code'] as String?)?.toLowerCase();

    // Strict Filter: only allow CC-licensed photos for legal safety.
    if (licenseCode == null || !_allowedLicenses.contains(licenseCode)) {
      return null;
    }

    final attribution = photo['attribution'] as String?;

    return INatPhoto(
      url: url,
      attribution: attribution,
      licenseCode: licenseCode,
    );
  }

  /// Normalizes the two response shapes used by iNaturalist for taxon names.
  List<Map<String, dynamic>> _extractTaxonNameRows(dynamic decoded) {
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }
    if (decoded is Map<String, dynamic>) {
      final results = decoded['results'];
      if (results is List) {
        return results.whereType<Map<String, dynamic>>().toList();
      }
    }
    return const [];
  }

  /// Converts a raw taxon-name row into a supported localized common name.
  INatCommonName? _parseCommonName(Map<String, dynamic> row) {
    final name = (row['name'] as String?)?.trim();
    final lexicon = (row['lexicon'] as String?)?.trim().toLowerCase();
    if (name == null || name.isEmpty || lexicon == null || lexicon.isEmpty) {
      return null;
    }

    final languageCode = _supportedLexicons[lexicon];
    if (languageCode == null) return null;

    return INatCommonName(
      languageCode: languageCode,
      name: name,
      position: row['position'] as int?,
      places: _extractPlaces(row['place_taxon_names'] as List<dynamic>?),
    );
  }

  /// Extracts all place-specific rankings attached to a taxon name.
  List<INatCommonNamePlace> _extractPlaces(List<dynamic>? placeTaxonNames) {
    if (placeTaxonNames == null || placeTaxonNames.isEmpty) return const [];

    final places = <INatCommonNamePlace>[];
    for (final item in placeTaxonNames.whereType<Map<String, dynamic>>()) {
      final placeId = item['place_id'] as int?;
      final position = item['position'] as int?;
      if (placeId == null || position == null) continue;
      places.add(INatCommonNamePlace(placeId: placeId, position: position));
    }
    return places;
  }

  /// Orders and deduplicates common names using iNat ranking metadata.
  List<INatCommonName> _rankCommonNames(List<INatCommonName> commonNames) {
    int bestPlacePosition(INatCommonName cn) => cn.places.isEmpty
        ? 999999
        : cn.places.map((p) => p.position).reduce((a, b) => a < b ? a : b);

    final sorted = [...commonNames]
      ..sort((a, b) {
        final aPosition = a.position ?? 999999;
        final bPosition = b.position ?? 999999;
        if (aPosition != bPosition) return aPosition.compareTo(bPosition);

        final aPlacePosition = bestPlacePosition(a);
        final bPlacePosition = bestPlacePosition(b);
        if (aPlacePosition != bPlacePosition) {
          return aPlacePosition.compareTo(bPlacePosition);
        }

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    final result = <INatCommonName>[];
    final seen = <String>{};

    for (final cn in sorted) {
      final normalized = cn.name
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ')
          .toLowerCase();
      if (normalized.isEmpty || seen.contains(normalized)) continue;
      seen.add(normalized);
      result.add(cn);
    }

    return result;
  }

  void _logDebug(String message) {
    if (_enableINatDebugLogging) {
      _log.debug(message);
    }
  }

  Uri _buildApiUri(
    String path, {
    Map<String, String>? queryParameters,
    Map<String, List<String>>? queryParametersAll,
  }) {
    final encodedPath = '$_apiBasePath$path';
    if ((queryParameters == null || queryParameters.isEmpty) &&
        (queryParametersAll == null || queryParametersAll.isEmpty)) {
      return Uri.https(_apiHost, encodedPath);
    }

    final mergedQueryParametersAll = <String, List<String>>{};
    if (queryParameters != null) {
      for (final entry in queryParameters.entries) {
        mergedQueryParametersAll[entry.key] = [entry.value];
      }
    }
    if (queryParametersAll != null) {
      for (final entry in queryParametersAll.entries) {
        mergedQueryParametersAll[entry.key] = entry.value;
      }
    }

    return Uri(
      scheme: 'https',
      host: _apiHost,
      path: encodedPath,
      query: _encodeQueryParametersAll(mergedQueryParametersAll),
    );
  }

  String _encodeQueryParametersAll(
    Map<String, List<String>> queryParametersAll,
  ) {
    final pairs = <String>[];
    for (final entry in queryParametersAll.entries) {
      final encodedKey = Uri.encodeQueryComponent(entry.key);
      for (final value in entry.value) {
        pairs.add('$encodedKey=${Uri.encodeQueryComponent(value)}');
      }
    }
    return pairs.join('&');
  }

  List<List<T>> _chunked<T>(List<T> items, int size) {
    final chunks = <List<T>>[];
    for (var index = 0; index < items.length; index += size) {
      final end = (index + size < items.length) ? index + size : items.length;
      chunks.add(items.sublist(index, end));
    }
    return chunks;
  }

  Future<http.Response> _executeGet(Uri uri, {Object? fields}) {
    if (fields == null) {
      return _client.get(uri, headers: {'User-Agent': _userAgent});
    }

    return _client.post(
      uri,
      headers: {
        'User-Agent': _userAgent,
        'X-HTTP-Method-Override': 'GET',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'fields': fields}),
    );
  }
}
