import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class WikiImage {
  final String thumbUrl;
  final String fullUrl;
  final String title;

  WikiImage({
    required this.thumbUrl,
    required this.fullUrl,
    required this.title,
  });
}

class ImageService {
  final http.Client _client;

  ImageService({http.Client? client}) : _client = client ?? http.Client();

  static const _userAgent = 'DiscereApp/1.1 (ch.feberle.discere; https://github.com/feberle/discere)';
  static const _wikiHeaders = {
    'User-Agent': _userAgent,
    'Accept': 'image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    'Accept-Encoding': 'gzip, deflate, br',
  };

  /// Used for species images (flashcards)
  Future<List<String>> downloadAndSaveImages(Set<String> urls) async {
    List<Future<String?>> downloadFutures =
        urls.map((url) => _downloadAndSaveImage(url)).toList();

    List<String?> results = await Future.wait(downloadFutures);

    return results.where((path) => path != null).cast<String>().toList();
  }

  /// Saves a cover image from the gallery to the app's local storage.
  Future<String> saveCoverImageFromGallery(String sourcePath) async {
    final dir = await _getCoverImageDir();
    final dest = File(
        p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}.jpg'));
    await File(sourcePath).copy(dest.path);
    return dest.path;
  }

  /// Searches Wikimedia Commons for images.
  Future<List<WikiImage>> searchWikiImages(String query) async {
    final uri = Uri.https('en.wikipedia.org', '/w/api.php', {
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
    if (response.statusCode != 200) throw Exception('Search failed (${response.statusCode})');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final pages = (data['query']?['pages'] as Map<String, dynamic>?)?.values ?? [];

    final images = <WikiImage>[];
    for (final page in pages) {
      final info = (page['imageinfo'] as List?)?.firstOrNull;
      if (info == null) continue;
      
      final thumbUrl = info['thumburl'] as String?;
      final fullUrl = info['url'] as String?;
      final title = page['title'] as String?;
      final mime = info['thumbmime'] as String? ?? '';
      
      if (thumbUrl == null || fullUrl == null || title == null || !mime.startsWith('image/')) {
        continue;
      }
      
      images.add(WikiImage(
        thumbUrl: thumbUrl,
        fullUrl: fullUrl,
        title: title,
      ));
    }
    return images;
  }

  /// Downloads a Wikimedia thumbnail (1200px) and saves it as a cover image.
  Future<String> downloadWikiThumbnail(String imageTitle, String fallbackUrl) async {
    // 1. Fetch high-res rendering info (1200px)
    final infoUri = Uri.parse('https://commons.wikimedia.org/w/api.php').replace(queryParameters: {
      'action': 'query',
      'titles': imageTitle,
      'prop': 'imageinfo',
      'iiprop': 'url|thumburl',
      'iiurlwidth': '1200', 
      'format': 'json',
      'origin': '*',
    });

    final infoRes = await _client.get(infoUri, headers: _wikiHeaders);
    if (infoRes.statusCode != 200) throw Exception('Wiki info fetch failed');

    final infoData = jsonDecode(infoRes.body) as Map<String, dynamic>;
    final page = (infoData['query']?['pages'] as Map<String, dynamic>?)?.values.firstOrNull;
    final info = (page?['imageinfo'] as List?)?.firstOrNull;
    final downloadUrl = info?['thumburl'] as String? ?? fallbackUrl;

    // 2. Download the image
    final response = await _client.get(Uri.parse(downloadUrl), headers: _wikiHeaders);
    if (response.statusCode != 200) throw Exception('Download failed (${response.statusCode})');

    // 3. Save to disk
    final dir = await _getCoverImageDir();
    final ext = p.extension(Uri.parse(downloadUrl).path);
    final suffix = ext.isNotEmpty ? ext : '.jpg';
    final dest = File(p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}$suffix'));
    await dest.writeAsBytes(response.bodyBytes);
    
    return dest.path;
  }

  /// Deletes an image file if it exists.
  Future<void> deleteImage(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Failed to delete image at $path: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<Directory> _getCoverImageDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'deck_covers'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<String?> _downloadAndSaveImage(String url) async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final String fileName = url.split('/').last;
    final String domainName = Uri.parse(url).host.replaceAll('.', '_');

    final String subDirectoryPath = '${directory.path}/$domainName';
    final Directory subDirectory = Directory(subDirectoryPath);
    if (!subDirectory.existsSync()) {
      subDirectory.createSync(recursive: true);
    }
    final String filePath = '$subDirectoryPath/$fileName';
    final file = File(filePath);
    if (await file.exists()) {
      return filePath;
    }

    try {
      final response = await _client.get(Uri.parse(url), headers: {'User-Agent': _userAgent});
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      }
    } catch (e) {
      if (kDebugMode) print(e.toString());
    }
    return null;
  }
}
