import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import './models/inat_photo.dart';

/// Fetches species photos from the iNaturalist API v1.
///
/// Uses the `/v1/taxa` endpoint to retrieve taxon photos by scientific name.
/// Rate limit: 60 requests/minute (iNat recommendation).
class INaturalistService {
  final http.Client _client;

  INaturalistService({http.Client? client})
      : _client = client ?? http.Client();

  static const _userAgent =
      'DiscereApp/1.1 (ch.feberle.discere; https://github.com/feberle/discere)';

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

  /// Fetches photos for a species by its full scientific name (e.g. "Amphiprion ocellaris").
  ///
  /// Returns an empty list if the taxon is not found.
  Future<List<INatPhoto>> fetchPhotos(String scientificName) async {
    try {
      // Step 1: Search for the taxon ID.
      final searchUri = Uri.https('api.inaturalist.org', '/v1/taxa', {
        'q': scientificName.trim(),
        'rank': 'species',
        'per_page': '10',
      });

      final searchResponse = await _client
          .get(searchUri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));

      if (searchResponse.statusCode != 200) return [];

      final searchData = jsonDecode(searchResponse.body) as Map<String, dynamic>;
      final results = searchData['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return [];

      // Find the first result that matches the scientific name exactly.
      int? taxonId;
      for (final r in results) {
        final name = r['name'] as String? ?? '';
        if (_isRelevantMatch(scientificName, name)) {
          taxonId = r['id'] as int?;
          break;
        }
      }

      if (taxonId == null) {
        if (kDebugMode) {
          debugPrint('iNat: no exact match for "$scientificName" in results.');
        }
        return [];
      }

      // Step 2: Fetch FULL taxon record to get the curated gallery.
      // Taxon search results often omit these photos.
      final taxonDetail = await _fetchTaxonDetail(taxonId);
      final curatedPhotos = taxonDetail != null ? _extractTaxonPhotos(taxonDetail) : <INatPhoto>[];
      
      // Step 3: Fetch observations until we reach 10 total CC-licensed photos.
      if (curatedPhotos.length < 10) {
        // Try Research Grade first (accurate).
        final observationPhotos = await _fetchObservationPhotos(
          taxonId, 
          qualityGrade: 'research',
          limit: 10 - curatedPhotos.length,
        );
        
        final allPhotos = [...curatedPhotos];
        final seenUrls = curatedPhotos.map((p) => p.url).toSet();
        
        for (final p in observationPhotos) {
          if (!seenUrls.contains(p.url)) {
            allPhotos.add(p);
            seenUrls.add(p.url);
          }
        }

        // Tier 3 Fallback: Still under 10? Fetch any quality grade (maximum coverage).
        if (allPhotos.length < 10) {
          final anyQualityPhotos = await _fetchObservationPhotos(
            taxonId,
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

        return allPhotos;
      }

      return curatedPhotos;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('iNat fetch error for "$scientificName": $e');
      }
      return [];
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
}



