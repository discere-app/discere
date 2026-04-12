import 'dart:convert';
import 'package:discere/shared/util/logger.dart';
import 'package:http/http.dart' as http;
import 'package:discere/shared/external/models/wiki_image.dart';

class WikiService {
  static final _log = Logger.forType(WikiService);
  final http.Client _client;

  WikiService({http.Client? client}) : _client = client ?? http.Client();

  static const _userAgent =
      'DiscereApp/1.1 (ch.feberle.discere; https://github.com/feberle/discere)';
  static const _wikiHeaders = {
    'User-Agent': _userAgent,
    'Accept': 'image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    'Accept-Encoding': 'gzip, deflate, br',
  };

  /// Searches Wikimedia Commons for images.
  Future<List<WikiImage>> searchWikiImages(String query) async {
    _log.debug('Searching Wikimedia Commons for "$query"');
    final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query',
      'generator': 'search',
      'gsrnamespace': '6', // File namespace
      'gsrsearch': query.trim(),
      'gsrlimit': '24',
      'prop': 'imageinfo',
      'iiprop': 'url|thumburl|thumbmime',
      'iiurlwidth': '320',
      'format': 'json',
      'origin': '*',
    });

    final response = await _client.get(uri, headers: _wikiHeaders);
    if (response.statusCode != 200) {
      throw Exception('Wiki search failed (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final pages =
        (data['query']?['pages'] as Map<String, dynamic>?)?.values ?? [];

    final images = <WikiImage>[];
    for (final page in pages) {
      final info = (page['imageinfo'] as List?)?.firstOrNull;
      if (info == null) continue;

      final thumbUrl = info['thumburl'] as String?;
      final fullUrl = info['url'] as String?;
      final title = page['title'] as String?;
      final mime = info['thumbmime'] as String? ?? '';

      if (thumbUrl == null ||
          fullUrl == null ||
          title == null ||
          !mime.startsWith('image/')) {
        continue;
      }

      images.add(WikiImage(thumbUrl: thumbUrl, fullUrl: fullUrl, title: title));
    }
    return images;
  }

  /// Fetches a high-resolution thumbnail URL for a given Wikimedia image title.
  Future<String> fetchHighResThumbUrl(
    String imageTitle, {
    int width = 1200,
  }) async {
    _log.debug(
      'Fetching high-res thumbnail for "$imageTitle" at width=$width',
    );
    final infoUri = Uri.parse('https://commons.wikimedia.org/w/api.php')
        .replace(
          queryParameters: {
            'action': 'query',
            'titles': imageTitle,
            'prop': 'imageinfo',
            'iiprop': 'url|thumburl',
            'iiurlwidth': width.toString(),
            'format': 'json',
            'origin': '*',
          },
        );

    final infoRes = await _client.get(infoUri, headers: _wikiHeaders);
    if (infoRes.statusCode != 200) throw Exception('Wiki info fetch failed');

    final infoData = jsonDecode(infoRes.body) as Map<String, dynamic>;
    final page = (infoData['query']?['pages'] as Map<String, dynamic>?)
        ?.values
        .firstOrNull;
    final info = (page?['imageinfo'] as List?)?.firstOrNull;

    final thumbUrl = info?['thumburl'] as String?;
    if (thumbUrl == null) throw Exception('No thumbnail URL found');

    return thumbUrl;
  }

  /// Gets the standard headers for Wikimedia requests.
  Map<String, String> get wikiHeaders => _wikiHeaders;
}
