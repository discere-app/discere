import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../external/wiki/models/wiki_image.dart';
import '../../external/wiki/wiki_service.dart';

class ImageService {
  final http.Client _client;
  final WikiService _wikiService;

  ImageService({http.Client? client, WikiService? wikiService})
      : _client = client ?? http.Client(),
        _wikiService = wikiService ?? WikiService(client: client);

  static const _userAgent =
      'DiscereApp/1.1 (ch.feberle.discere; https://github.com/feberle/discere)';

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

  /// Searches online for images (currently Wikimedia Commons).
  Future<List<WikiImage>> searchImagesOnline(String query) async {
    return _wikiService.searchWikiImages(query);
  }

  /// Downloads an online image and saves it to local storage.
  Future<String> downloadImageOnline(
      String imageTitle, String fallbackUrl) async {
    // 1. Fetch high-res rendering info (1200px) from the wiki service
    final downloadUrl = await _wikiService
        .fetchHighResThumbUrl(imageTitle)
        .catchError((_) => fallbackUrl);

    // 2. Download the image
    final response = await _client.get(Uri.parse(downloadUrl),
        headers: _wikiService.wikiHeaders);
    if (response.statusCode != 200) {
      throw Exception('Download failed (${response.statusCode})');
    }

    // 3. Save to disk
    final dir = await _getCoverImageDir();
    final ext = p.extension(Uri.parse(downloadUrl).path);
    final suffix = ext.isNotEmpty ? ext : '.jpg';
    final dest = File(
        p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}$suffix'));
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
