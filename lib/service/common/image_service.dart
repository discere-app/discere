import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
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

  /// Downloads and caches images, returning a mapping of original URLs to their local file paths.
  Future<Map<String, String>> downloadAndSaveImagesMap(Set<String> urls) async {
    final Map<String, String> urlToLocalPath = {};
    
    final futures = urls.map((url) async {
      final localPath = await _downloadAndSaveImage(url);
      if (localPath != null) {
        urlToLocalPath[url] = localPath;
      }
    });
    
    await Future.wait(futures);
    return urlToLocalPath;
  }

  /// Saves a picked or downloaded image as a permanent deck cover.
  Future<String> saveCoverImage(String sourcePath) async {
    final dir = await _getCoverImageDir();
    final ext = p.extension(sourcePath);
    final suffix = ext.isNotEmpty ? ext : '.jpg';
    final dest = File(
        p.join(dir.path, 'cover_${DateTime.now().millisecondsSinceEpoch}$suffix'));
    await File(sourcePath).copy(dest.path);
    return dest.path;
  }

  /// Downloads a remote image and saves it permanently as a deck cover.
  Future<String> downloadAndSaveDeckCover(String url) async {
    final response = await _client.get(Uri.parse(url), headers: {'User-Agent': _userAgent}).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Download failed (${response.statusCode})');
    }

    final dir = await _getCoverImageDir();
    final ext = p.extension(Uri.parse(url).path);
    final suffix = ext.isNotEmpty ? ext : '.jpg';
    final dest = File(
        p.join(dir.path, 'cover_remote_${DateTime.now().millisecondsSinceEpoch}$suffix'));
    
    await dest.writeAsBytes(response.bodyBytes);
    return dest.path;
  }

  /// Searches online for images (currently Wikimedia Commons).
  Future<List<WikiImage>> searchImagesOnline(String query) async {
    return _wikiService.searchWikiImages(query);
  }

  /// Downloads an online image and saves it to a temporary local storage.
  /// Used by ImagePicker before the user decides to permanently save it.
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

    // 3. Save to disk (temporarily)
    final dir = await getTemporaryDirectory();
    final ext = p.extension(Uri.parse(downloadUrl).path);
    final suffix = ext.isNotEmpty ? ext : '.jpg';
    final dest = File(
        p.join(dir.path, 'temp_img_${DateTime.now().millisecondsSinceEpoch}$suffix'));
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
      if (kDebugMode) {
        debugPrint('Failed to delete image at $path: $e');
      }
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
    
    // Use MD5 hash of URL for unique, collision-safe filename (prevents "medium.jpeg" collisions)
    final String urlHash = md5.convert(utf8.encode(url)).toString();
    final String ext = p.extension(Uri.parse(url).path);
    final String fileName = '$urlHash${ext.isNotEmpty ? ext : '.jpg'}';

    final String domainName = Uri.parse(url).host.replaceAll('.', '_');
    final String subDirectoryPath = p.join(directory.path, domainName);
    
    final Directory subDirectory = Directory(subDirectoryPath);
    if (!subDirectory.existsSync()) {
      subDirectory.createSync(recursive: true);
    }
    final String filePath = p.join(subDirectoryPath, fileName);
    final file = File(filePath);
    if (await file.exists()) {
      return filePath;
    }

    try {
      final response = await _client.get(Uri.parse(url), headers: {'User-Agent': _userAgent}).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      }
    } catch (e) {
      if (kDebugMode) debugPrint(e.toString());
    }
    return null;
  }
}
