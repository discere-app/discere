import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:discere/shared/util/concurrency_utils.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageService {
  static final _log = Logger.forType(ImageService);
  static const _maxConcurrentDownloads = 6;
  static const _referenceImageTimeout = Duration(seconds: 5);
  static const _deckCoverTimeout = Duration(seconds: 10);

  final http.Client _client;

  ImageService({required http.Client client}) : _client = client;

  static const _userAgent =
      'DiscereApp/1.1 (ch.feberle.discere; https://github.com/feberle/discere)';

  /// Used for species images (flashcards)
  Future<List<String>> downloadAndSaveImages(Set<String> urls) async {
    final results = await runWithConcurrency<String, String?>(
      urls.toList(),
      maxConcurrent: _maxConcurrentDownloads,
      task: (url) =>
          _downloadAndSaveImage(url, storageDirectory: 'reference_images'),
    );

    return results.where((path) => path != null).cast<String>().toList();
  }

  /// Downloads and caches images, returning a mapping of original URLs to their local file paths.
  Future<Map<String, String>> downloadAndSaveImagesMap(Set<String> urls) async {
    final Map<String, String> urlToLocalPath = {};
    final entries = await runWithConcurrency<String, MapEntry<String, String>?>(
      urls.toList(),
      maxConcurrent: _maxConcurrentDownloads,
      task: (url) async {
        final localPath = await _downloadAndSaveImage(
          url,
          storageDirectory: 'reference_images',
        );
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

  /// Returns already-saved local paths for the given URLs without downloading
  /// missing files.
  Future<Map<String, String>> resolveSavedUrlMap(
    Set<String> urls, {
    String storageDirectory = 'reference_images',
    Set<String> legacyDirectories = const {},
  }) async {
    final urlToLocalPath = <String, String>{};

    for (final url in urls) {
      if (url.isEmpty) continue;
      final filePath = await _resolveExistingImagePath(
        url,
        storageDirectory: storageDirectory,
        legacyDirectories: legacyDirectories,
      );
      if (filePath != null) {
        urlToLocalPath[url] = filePath;
      }
    }

    return urlToLocalPath;
  }

  /// Downloads URLs directly and returns a mapping to local file paths.
  ///
  /// Callers can override [maxConcurrent] when a host should be treated more
  /// conservatively than the default reference-image pipeline. Discere uses
  /// this to keep iNaturalist image downloads serial while still allowing
  /// bundled/reference sources such as FishBase or SeaLifeBase to fan out in
  /// parallel.
  Future<Map<String, String>> downloadAndSaveUrlMap(
    Set<String> urls, {
    String storageDirectory = 'reference_images',
    int maxConcurrent = _maxConcurrentDownloads,
    void Function(int completed, int total)? onProgress,
  }) async {
    final uniqueUrls = urls.where((url) => url.isNotEmpty).toSet();
    final total = uniqueUrls.length;
    if (total == 0) {
      onProgress?.call(0, 0);
      return {};
    }

    final Map<String, String> urlToLocalPath = {};
    var completed = 0;

    final entries = await runWithConcurrency<String, MapEntry<String, String>?>(
      uniqueUrls.toList(),
      maxConcurrent: maxConcurrent,
      task: (url) async {
        final localPath = await _downloadAndSaveImage(
          url,
          storageDirectory: storageDirectory,
        );
        completed++;
        onProgress?.call(completed, total);
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
    _log.debug('Downloading deck cover from $url');
    final responseBytes = await _downloadBytes(
      Uri.parse(url),
      headers: {'User-Agent': _userAgent},
      timeout: _deckCoverTimeout,
    );

    final dir = await _getCoverImageDir();
    final ext = p.extension(Uri.parse(url).path);
    final suffix = ext.isNotEmpty ? ext : '.jpg';
    final dest = File(
      p.join(
        dir.path,
        'cover_remote_${DateTime.now().millisecondsSinceEpoch}$suffix',
      ),
    );

    await dest.writeAsBytes(responseBytes);
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
      _log.warn('Failed to delete image at $path: $e');
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<Directory> _getCoverImageDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'deck_covers'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<String?> _downloadAndSaveImage(
    String url, {
    required String storageDirectory,
  }) async {
    final existingPath = await _resolveExistingImagePath(
      url,
      storageDirectory: storageDirectory,
    );
    if (existingPath != null) {
      return existingPath;
    }

    final filePath = await _buildLocalImagePath(
      url,
      storageDirectory: storageDirectory,
    );
    final subDirectory = File(filePath).parent;
    if (!subDirectory.existsSync()) {
      subDirectory.createSync(recursive: true);
    }
    final file = File(filePath);
    final tempFile = File('$filePath.part');

    try {
      _log.debug(
        'Downloading reference image from $url into $storageDirectory',
      );
      final responseBytes = await _downloadBytes(
        Uri.parse(url),
        headers: {'User-Agent': _userAgent},
        timeout: _referenceImageTimeout,
      );
      await tempFile.writeAsBytes(responseBytes);
      await tempFile.rename(file.path);
      return file.path;
    } catch (e) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      _log.warn(e.toString());
    }
    return null;
  }

  Future<List<int>> _downloadBytes(
    Uri url, {
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    final response = await _client.get(url, headers: headers).timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        'Request timed out for $url after ${timeout.inSeconds}s',
        timeout,
      ),
    );
    if (response.statusCode != 200) {
      throw HttpDownloadException(url, response.statusCode);
    }
    return response.bodyBytes;
  }

  Future<String?> _resolveExistingImagePath(
    String url, {
    required String storageDirectory,
    Set<String> legacyDirectories = const {},
  }) async {
    final canonicalPath = await _buildLocalImagePath(
      url,
      storageDirectory: storageDirectory,
    );
    if (await File(canonicalPath).exists()) {
      return canonicalPath;
    }

    for (final legacyDirectory in legacyDirectories) {
      final legacyPath = await _buildLocalImagePath(
        url,
        storageDirectory: legacyDirectory,
      );
      if (await File(legacyPath).exists()) {
        return legacyPath;
      }
    }

    return null;
  }

  Future<String> _buildLocalImagePath(
    String url, {
    required String storageDirectory,
  }) async {
    final directory = await getApplicationDocumentsDirectory();

    // Use MD5 hash of URL for unique, collision-safe filename.
    final urlHash = md5.convert(utf8.encode(url)).toString();
    final ext = p.extension(Uri.parse(url).path);
    final fileName = '$urlHash${ext.isNotEmpty ? ext : '.jpg'}';

    final subDirectoryPath = p.join(
      directory.path,
      storageDirectory,
      Uri.parse(url).host.replaceAll('.', '_'),
    );

    return p.join(subDirectoryPath, fileName);
  }
}

final class HttpDownloadException implements Exception {
  final Uri url;
  final int statusCode;

  const HttpDownloadException(this.url, this.statusCode);

  bool get isRetryable => statusCode == 429 || statusCode >= 500;

  @override
  String toString() => 'Download failed ($statusCode) for $url';
}
