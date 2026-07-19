import 'dart:async';
import 'dart:convert';

import 'package:discere/shared/util/logger.dart';
import 'package:http/http.dart' as http;

class WikipediaSummary {
  final String extract;
  final String languageCode;

  const WikipediaSummary({required this.extract, required this.languageCode});
}

/// Direct client for the public Wikipedia/Wikimedia REST and Action APIs.
///
/// Deliberately independent from `INaturalistService` — iNaturalist's own
/// `wikipedia_summary` field only reliably returns English text (a
/// `?locale=` query param yields no translation fallback), and we don't want
/// this feature to add extra iNaturalist calls/rate-limit pressure. Instead
/// this fetches the article title from the already-cached `wikipedia_url`
/// (persisted during iNat enrichment for the external-links chip) and talks
/// to Wikipedia directly.
class WikipediaService {
  static final _log = Logger.forType(WikipediaService);
  static const _userAgent =
      'DiscereApp/1.1 (ch.feberle.discere; https://github.com/feberle/discere)';
  static const _timeout = Duration(seconds: 8);

  final http.Client _client;

  WikipediaService({required http.Client client}) : _client = client;

  /// Fetches a plain-text lead-paragraph summary for the article at
  /// [wikipediaUrl], preferring [localeCode]. If no translation exists in
  /// that language, falls back to the article's own (source) language.
  Future<WikipediaSummary?> getSummary({
    required String wikipediaUrl,
    required String localeCode,
  }) async {
    final source = _parseWikipediaUrl(wikipediaUrl);
    if (source == null) return null;

    if (source.languageCode == localeCode) {
      return _fetchSummary(languageCode: localeCode, title: source.title);
    }

    final localizedTitle = await _resolveLocalizedTitle(
      languageCode: source.languageCode,
      title: source.title,
      targetLanguageCode: localeCode,
    );
    if (localizedTitle != null) {
      final localized = await _fetchSummary(
        languageCode: localeCode,
        title: localizedTitle,
      );
      if (localized != null) return localized;
    }

    return _fetchSummary(
      languageCode: source.languageCode,
      title: source.title,
    );
  }

  ({String languageCode, String title})? _parseWikipediaUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    const suffix = '.wikipedia.org';
    final host = uri.host;
    if (!host.endsWith(suffix) || host.length <= suffix.length) return null;
    final languageCode = host.substring(0, host.length - suffix.length);

    final segments = uri.pathSegments;
    if (segments.length < 2 || segments.first != 'wiki') return null;
    final title = segments.sublist(1).join('/');
    if (title.isEmpty) return null;

    return (languageCode: languageCode, title: title);
  }

  Future<String?> _resolveLocalizedTitle({
    required String languageCode,
    required String title,
    required String targetLanguageCode,
  }) async {
    final uri = Uri.https('$languageCode.wikipedia.org', '/w/api.php', {
      'action': 'query',
      'titles': title,
      'prop': 'langlinks',
      'lllang': targetLanguageCode,
      'redirects': '1',
      'format': 'json',
      'formatversion': '2',
    });
    try {
      final response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(_timeout);
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final query = body['query'] as Map<String, dynamic>?;
      final pages = query?['pages'] as List<dynamic>?;
      if (pages == null || pages.isEmpty) return null;

      final langlinks = (pages.first as Map<String, dynamic>)['langlinks']
          as List<dynamic>?;
      if (langlinks == null || langlinks.isEmpty) return null;

      return (langlinks.first as Map<String, dynamic>)['title'] as String?;
    } catch (error) {
      _log.debug(
        'Wikipedia langlinks lookup failed for '
        '$languageCode:$title -> $targetLanguageCode: $error',
      );
      return null;
    }
  }

  Future<WikipediaSummary?> _fetchSummary({
    required String languageCode,
    required String title,
  }) async {
    final uri = Uri(
      scheme: 'https',
      host: '$languageCode.wikipedia.org',
      pathSegments: ['api', 'rest_v1', 'page', 'summary', title],
    );
    try {
      final response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(_timeout);
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final extract = body['extract'] as String?;
      if (extract == null || extract.isEmpty) return null;

      return WikipediaSummary(extract: extract, languageCode: languageCode);
    } catch (error) {
      _log.debug(
        'Wikipedia summary fetch failed for $languageCode:$title: $error',
      );
      return null;
    }
  }
}
