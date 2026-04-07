import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../model/biology/picture.dart';
import '../../external/wiki/models/wiki_image.dart';
import '../../external/wiki/wiki_service.dart';

class ImageService {
  static const _maxConcurrentDownloads = 6;

  final http.Client _client;
  final WikiService _wikiService;

  ImageService({http.Client? client, WikiService? wikiService})
    : _client = client ?? http.Client(),
      _wikiService = wikiService ?? WikiService(client: client);

  static const _userAgent =
      'DiscereApp/1.1 (ch.feberle.discere; https://github.com/feberle/discere)';

  /// Used for species images (flashcards)
  Future<List<String>> downloadAndSaveImages(Set<String> urls) async {
    final results = await _runWithConcurrency<String, String?>(
      urls.toList(),
      maxConcurrent: _maxConcurrentDownloads,
      task: _downloadAndSaveImage,
    );

    return results.where((path) => path != null).cast<String>().toList();
  }

  /// Downloads and caches images, returning a mapping of original URLs to their local file paths.
  Future<Map<String, String>> downloadAndSaveImagesMap(Set<String> urls) async {
    final Map<String, String> urlToLocalPath = {};
    final entries =
        await _runWithConcurrency<String, MapEntry<String, String>?>(
          urls.toList(),
          maxConcurrent: _maxConcurrentDownloads,
          task: (url) async {
            final localPath = await _downloadAndSaveImage(url);
            if (localPath == null) return null;
            return MapEntry(url, localPath);
          },
        );

    for (final entry in entries) {
      if (entry == null) continue;
      urlToLocalPath[entry.key] = entry.value;
    }
    return urlToLocalPath;
  }

  /// Returns already-saved local paths for the given pictures without
  /// downloading missing files.
  Future<Map<String, String>> resolveSavedPicturesMap(
    Iterable<Picture> pictures,
  ) async {
    final urlToLocalPath = <String, String>{};

    for (final picture in pictures) {
      final url = picture.url;
      if (url == null || url.isEmpty) continue;

      final filePath = await _buildLocalImagePath(url, picture: picture);
      if (await File(filePath).exists()) {
        urlToLocalPath[url] = filePath;
      }
    }

    return urlToLocalPath;
  }

  /// Downloads pictures directly, regardless of whether they come from the
  /// reference dataset or an external source such as iNaturalist.
  ///
  /// Files are still de-duplicated by the URL hash, so different images with
  /// the same filename do not collide.
  Future<Map<String, String>> downloadAndSavePicturesMap(
    Iterable<Picture> pictures, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final picturesByUrl = <String, Picture>{};
    for (final picture in pictures) {
      final url = picture.url;
      if (url == null || url.isEmpty) continue;
      picturesByUrl.putIfAbsent(url, () => picture);
    }

    final total = picturesByUrl.length;
    if (total == 0) {
      onProgress?.call(0, 0);
      return {};
    }

    final Map<String, String> urlToLocalPath = {};
    var completed = 0;

    final entries =
        await _runWithConcurrency<
          MapEntry<String, Picture>,
          MapEntry<String, String>?
        >(
          picturesByUrl.entries.toList(),
          maxConcurrent: _maxConcurrentDownloads,
          task: (entry) async {
            final localPath = await _downloadAndSaveImage(
              entry.key,
              picture: entry.value,
            );
            completed++;
            onProgress?.call(completed, total);
            if (localPath == null) return null;
            return MapEntry(entry.key, localPath);
          },
        );

    for (final entry in entries) {
      if (entry == null) continue;
      urlToLocalPath[entry.key] = entry.value;
    }
    return urlToLocalPath;
  }

  /// Saves a picked or downloaded image as a permanent deck cover.
  Future<String> saveCoverImage(String sourcePath) async {
    final dir = await _getCoverImageDir();
    final ext = p.extension(sourcePath);
    final suffix = ext.isNotEmpty ? ext : '.jpg';
    final dest = File(
      p.join(dir.path, 'cover_${DateTime.now().millisecondsSinceEpoch}$suffix'),
    );
    await File(sourcePath).copy(dest.path);
    return dest.path;
  }

  /// Downloads a remote image and saves it permanently as a deck cover.
  Future<String> downloadAndSaveDeckCover(String url) async {
    final response = await _client
        .get(Uri.parse(url), headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Download failed (${response.statusCode})');
    }

    final dir = await _getCoverImageDir();
    final ext = p.extension(Uri.parse(url).path);
    final suffix = ext.isNotEmpty ? ext : '.jpg';
    final dest = File(
      p.join(
        dir.path,
        'cover_remote_${DateTime.now().millisecondsSinceEpoch}$suffix',
      ),
    );

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
    String imageTitle,
    String fallbackUrl,
  ) async {
    // 1. Fetch high-res rendering info (1200px) from the wiki service
    final downloadUrl = await _wikiService
        .fetchHighResThumbUrl(imageTitle)
        .catchError((_) => fallbackUrl);

    // 2. Download the image
    final response = await _client.get(
      Uri.parse(downloadUrl),
      headers: _wikiService.wikiHeaders,
    );
    if (response.statusCode != 200) {
      throw Exception('Download failed (${response.statusCode})');
    }

    // 3. Save to disk (temporarily)
    final dir = await getTemporaryDirectory();
    final ext = p.extension(Uri.parse(downloadUrl).path);
    final suffix = ext.isNotEmpty ? ext : '.jpg';
    final dest = File(
      p.join(
        dir.path,
        'temp_img_${DateTime.now().millisecondsSinceEpoch}$suffix',
      ),
    );
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

  Future<String?> _downloadAndSaveImage(String url, {Picture? picture}) async {
    final filePath = await _buildLocalImagePath(url, picture: picture);
    final subDirectory = File(filePath).parent;
    if (!subDirectory.existsSync()) {
      subDirectory.createSync(recursive: true);
    }
    final file = File(filePath);
    if (await file.exists()) {
      return filePath;
    }

    try {
      final response = await _client
          .get(Uri.parse(url), headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      }
    } catch (e) {
      if (kDebugMode) debugPrint(e.toString());
    }
    return null;
  }

  Future<String> _buildLocalImagePath(String url, {Picture? picture}) async {
    final directory = await getApplicationDocumentsDirectory();

    // Use MD5 hash of URL for unique, collision-safe filename.
    final urlHash = md5.convert(utf8.encode(url)).toString();
    final ext = p.extension(Uri.parse(url).path);
    final fileName = '$urlHash${ext.isNotEmpty ? ext : '.jpg'}';

    final subDirectoryPath = p.join(
      directory.path,
      _imageSourceDirectory(picture),
      Uri.parse(url).host.replaceAll('.', '_'),
    );

    return p.join(subDirectoryPath, fileName);
  }

  String _imageSourceDirectory(Picture? picture) {
    if (picture?.origin.toLowerCase() == 'inaturalist') {
      return 'external_images';
    }
    return 'reference_images';
  }

  Future<List<R>> _runWithConcurrency<T, R>(
    List<T> items, {
    required int maxConcurrent,
    required Future<R> Function(T item) task,
  }) async {
    if (items.isEmpty) return [];

    final results = List<R?>.filled(items.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final currentIndex = nextIndex;
        if (currentIndex >= items.length) return;
        nextIndex++;
        results[currentIndex] = await task(items[currentIndex]);
      }
    }

    final workerCount = items.length < maxConcurrent
        ? items.length
        : maxConcurrent;
    await Future.wait(List.generate(workerCount, (_) => worker()));

    return results.cast<R>();
  }
}
