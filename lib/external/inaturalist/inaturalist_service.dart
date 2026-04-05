import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import './models/inat_photo.dart';
import './models/inat_common_name.dart';

/// Small gateway for Discere's iNaturalist integration.
///
/// The service resolves iNaturalist taxon IDs by scientific name and then
/// exposes two capabilities used during post-import enrichment:
/// fetching legally usable photos and fetching ranked multilingual common
/// names for supported app languages.
class INaturalistService {
  final http.Client _client;

  INaturalistService({http.Client? client}) : _client = client ?? http.Client();

  static const _userAgent =
      'DiscereApp/1.1 (ch.feberle.discere; https://github.com/feberle/discere)';

  static const Map<String, String> _supportedLexicons = {
    'english': 'en',
    'german': 'de',
    'french': 'fr',
    'spanish': 'es',
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
  /// Returns up to [perPage] active species/subspecies candidates. Each entry
  /// contains the scientific name, the iNat taxon ID, and the preferred common
  /// name if available. Returns an empty list on network errors or timeouts so
  /// callers can treat this as a best-effort supplement.
  Future<List<Map<String, dynamic>>> searchTaxa(
    String query, {
    int perPage = 20,
  }) async {
    try {
      final uri = Uri.https('api.inaturalist.org', '/v1/taxa', {
        'q': query.trim(),
        'per_page': perPage.toString(),
        'is_active': 'true',
        'rank': 'species,subspecies',
      });

      final response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return const [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>?;
      if (results == null) return const [];

      return results.whereType<Map<String, dynamic>>().map((r) {
        return <String, dynamic>{
          'id': r['id'] as int?,
          'scientific_name': r['name'] as String? ?? '',
          'preferred_common_name': r['preferred_common_name'] as String?,
          'matched_term': r['matched_term'] as String?,
        };
      }).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('iNat searchTaxa error for "$query": $e');
      }
      return const [];
    }
  }

  /// Fetches photos for a species by its full scientific name (e.g. "Amphiprion ocellaris").
  ///
  /// If [taxonId] is provided, it skips the search and fetches directly.
  /// Returns a record with the discovered taxonId and the list of photos.
  Future<({int taxonId, List<INatPhoto> photos})?> fetchPhotos(
    String scientificName, {
    int? taxonId,
  }) async {
    try {
      final resolvedTaxonId = await _resolveTaxonId(
        scientificName,
        taxonId: taxonId,
      );

      if (resolvedTaxonId == null) {
        if (kDebugMode) {
          debugPrint('iNat: could not resolve taxon for "$scientificName".');
        }
        return null;
      }

      // Step 2: Fetch FULL taxon record to get the curated gallery.
      final taxonDetail = await _fetchTaxonDetail(resolvedTaxonId);
      final curatedPhotos = taxonDetail != null
          ? _extractTaxonPhotos(taxonDetail)
          : <INatPhoto>[];

      // Step 3: Fetch observations until we reach 10 total CC-licensed photos.
      List<INatPhoto> allPhotos = [...curatedPhotos];

      if (allPhotos.length < 10) {
        final observationPhotos = await _fetchObservationPhotos(
          resolvedTaxonId,
          qualityGrade: 'research',
          limit: 10 - curatedPhotos.length,
        );

        final seenUrls = curatedPhotos.map((p) => p.url).toSet();

        for (final p in observationPhotos) {
          if (!seenUrls.contains(p.url)) {
            allPhotos.add(p);
            seenUrls.add(p.url);
          }
        }

        // Tier 3 Fallback
        if (allPhotos.length < 10) {
          final anyQualityPhotos = await _fetchObservationPhotos(
            resolvedTaxonId,
            qualityGrade: 'any',
            limit: 10 - allPhotos.length,
          );

          for (final p in anyQualityPhotos) {
            if (!seenUrls.contains(p.url)) {
              allPhotos.add(p);
              seenUrls.add(p.url);
            }
          }
        }
      }

      return (taxonId: resolvedTaxonId, photos: allPhotos);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('iNat fetch error for "$scientificName": $e');
      }
      return null;
    }
  }

  /// Fetches ranked common names for a taxon.
  ///
  /// Supports species and higher taxonomy ranks. The returned map is keyed by
  /// app language code (`de`, `en`, `fr`, `es`) and values are ordered from
  /// best to worst candidate according to iNaturalist ranking metadata.
  Future<({int taxonId, Map<String, List<String>> commonNames})?>
  fetchCommonNames(String scientificName, {int? taxonId, String? rank}) async {
    try {
      final resolvedTaxonId = await _resolveTaxonId(
        scientificName,
        taxonId: taxonId,
        rank: rank,
      );
      if (resolvedTaxonId == null) return null;

      final uri = Uri.https('www.inaturalist.org', '/taxon_names.json', {
        'taxon_id': resolvedTaxonId.toString(),
        'per_page': '200',
      });
      final response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      final rows = _extractTaxonNameRows(decoded);
      final namesByLanguage = <String, List<INatCommonName>>{};

      for (final row in rows) {
        final commonName = _parseCommonName(row);
        if (commonName == null) continue;
        namesByLanguage
            .putIfAbsent(commonName.languageCode, () => [])
            .add(commonName);
      }

      final deduped = <String, List<String>>{};
      for (final entry in namesByLanguage.entries) {
        final rankedNames = _rankCommonNames(entry.value);
        if (rankedNames.isNotEmpty) {
          deduped[entry.key] = rankedNames;
        }
      }

      return (taxonId: resolvedTaxonId, commonNames: deduped);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('iNat common-name fetch error for "$scientificName": $e');
      }
      return null;
    }
  }

  /// Fetches a single taxon record by ID to retrieve the curated gallery.
  Future<Map<String, dynamic>?> _fetchTaxonDetail(int taxonId) async {
    try {
      final uri = Uri.https('api.inaturalist.org', '/v1/taxa/$taxonId');
      final response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      return results.first as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Fetches photos from the top observations for a taxon.
  /// Strictly filters for CC licensing as per legal safety requirements.
  Future<List<INatPhoto>> _fetchObservationPhotos(
    int taxonId, {
    String qualityGrade = 'research',
    int limit = 10,
  }) async {
    try {
      final uri = Uri.https('api.inaturalist.org', '/v1/observations', {
        'taxon_id': taxonId.toString(),
        'quality_grade': qualityGrade,
        'photos': 'true',
        'photo_licensed': 'true', // Only licensed (CC) images
        'per_page': '50', // Search pool for filtering
        'order_by': 'votes', // Prioritize popular/beautiful shots
      });

      final response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>?;
      if (results == null) return [];

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
      return photos;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('iNat observation fallback error: $e');
      }
      return [];
    }
  }

  /// Checks if the API result is a relevant match for the query.
  bool _isRelevantMatch(String query, String result) {
    return result.toLowerCase().trim() == query.toLowerCase().trim();
  }

  /// Resolves an iNaturalist taxon ID from a scientific name and optional rank.
  Future<int?> _resolveTaxonId(
    String scientificName, {
    int? taxonId,
    String? rank,
  }) async {
    if (taxonId != null) return taxonId;

    final queryParameters = <String, String>{
      'q': scientificName.trim(),
      'per_page': '10',
    };
    if (rank != null && rank.trim().isNotEmpty) {
      queryParameters['rank'] = rank.trim();
    } else {
      queryParameters['rank'] = 'species';
    }

    final searchUri = Uri.https(
      'api.inaturalist.org',
      '/v1/taxa',
      queryParameters,
    );

    final searchResponse = await _client
        .get(searchUri, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 10));

    if (searchResponse.statusCode != 200) return null;

    final searchData = jsonDecode(searchResponse.body) as Map<String, dynamic>;
    final results = searchData['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;

    for (final r in results) {
      final name = r['name'] as String? ?? '';
      final matchedTerm = r['matched_term'] as String?;

      if (_isRelevantMatch(scientificName, name) ||
          (matchedTerm != null &&
              _isRelevantMatch(scientificName, matchedTerm))) {
        return r['id'] as int?;
      }
    }

    return results.first['id'] as int?;
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

    final placePosition = _extractBestPlacePosition(
      row['place_taxon_names'] as List<dynamic>?,
    );

    return INatCommonName(
      languageCode: languageCode,
      name: name,
      position: row['position'] as int?,
      placePosition: placePosition,
    );
  }

  /// Picks the strongest place-specific ranking attached to a taxon name.
  int? _extractBestPlacePosition(List<dynamic>? placeTaxonNames) {
    if (placeTaxonNames == null || placeTaxonNames.isEmpty) return null;

    int? best;
    for (final item in placeTaxonNames.whereType<Map<String, dynamic>>()) {
      final position = item['position'] as int?;
      if (position == null) continue;
      if (best == null || position < best) {
        best = position;
      }
    }
    return best;
  }

  /// Orders and deduplicates common names using iNat ranking metadata.
  List<String> _rankCommonNames(List<INatCommonName> commonNames) {
    final sorted = [...commonNames]
      ..sort((a, b) {
        final aPosition = a.position ?? 999999;
        final bPosition = b.position ?? 999999;
        if (aPosition != bPosition) return aPosition.compareTo(bPosition);

        final aPlacePosition = a.placePosition ?? 999999;
        final bPlacePosition = b.placePosition ?? 999999;
        if (aPlacePosition != bPlacePosition) {
          return aPlacePosition.compareTo(bPlacePosition);
        }

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    final names = <String>[];
    final seen = <String>{};

    for (final commonName in sorted) {
      final normalized = commonName.name
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ')
          .toLowerCase();
      if (normalized.isEmpty || seen.contains(normalized)) continue;
      seen.add(normalized);
      names.add(commonName.name.trim());
    }

    return names;
  }
}
