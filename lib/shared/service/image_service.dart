import 'dart:async';
import 'dart:io';

import 'package:discere/shared/service/cached_image_store.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/image_download_outcome.dart';
import 'package:discere/shared/service/image_host_fallbacks.dart';
import 'package:discere/shared/util/concurrency_utils.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class ImageService {
  static final _log = Logger.forType(ImageService);
  static const _maxConcurrentDownloads = 6;
  static const _referenceImageTimeout = Duration(seconds: 5);
  static const _deckCoverTimeout = Duration(seconds: 10);

  /// The 4xx statuses that describe the host's state rather than the
  /// requested image: timed out waiting, too early, too many requests.
  static const _hostSideClientErrors = {408, 425, 429};

  final http.Client _client;
  final HostCooldownTracker _hostCooldownTracker;
  final CachedImageStore _store;

  ImageService({
    required http.Client client,
    required HostCooldownTracker hostCooldownTracker,
    required CachedImageStore store,
  }) : _client = client,
       _hostCooldownTracker = hostCooldownTracker,
       _store = store;

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
      final filePath = await _store.existingPathFor(
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

  /// Downloads URLs directly and returns a mapping to local file paths —
  /// [downloadAndSaveUrls] for callers that only need what was saved.
  Future<Map<String, String>> downloadAndSaveUrlMap(
    Set<String> urls, {
    String storageDirectory = 'reference_images',
    int maxConcurrent = _maxConcurrentDownloads,
    bool skipIfHostCoolingDown = false,
    void Function(int completed, int total)? onProgress,
  }) async {
    final outcomes = await downloadAndSaveUrls(
      urls,
      storageDirectory: storageDirectory,
      maxConcurrent: maxConcurrent,
      skipIfHostCoolingDown: skipIfHostCoolingDown,
      onProgress: onProgress,
    );
    return {
      for (final MapEntry(key: url, value: outcome) in outcomes.entries)
        if (outcome case ImageSaved(:final localPath)) url: localPath,
    };
  }

  /// Downloads URLs directly and reports how each one ended, keyed by URL.
  ///
  /// Callers can override [maxConcurrent] when a host should be treated more
  /// conservatively than the default reference-image pipeline. Discere uses
  /// this to keep iNaturalist image downloads serial while still allowing
  /// bundled/reference sources such as FishBase or SeaLifeBase to fan out in
  /// parallel.
  ///
  /// [skipIfHostCoolingDown]: when true, a URL whose host is currently in a
  /// [HostCooldownTracker] cooldown is skipped outright instead of issuing
  /// the request (which would otherwise block for the remaining cooldown
  /// duration inside the shared HTTP client), and reported as
  /// [ImageHostUnreachable]. Used by bounded, interactive callers such as
  /// [LocalSpeciesImageService.resolveEnsuringSingleImage] that need a fast
  /// best-effort attempt, and by the reference-image worker, which would
  /// otherwise let every species of a large batch wait out the same outage.
  ///
  /// A URL whose host has a problem is tried once more from the host's
  /// mirror in [imageHostFallbacks], if it has one.
  Future<Map<String, ImageDownloadOutcome>> downloadAndSaveUrls(
    Set<String> urls, {
    String storageDirectory = 'reference_images',
    int maxConcurrent = _maxConcurrentDownloads,
    bool skipIfHostCoolingDown = false,
    void Function(int completed, int total)? onProgress,
  }) async {
    final uniqueUrls = urls.where((url) => url.isNotEmpty).toList();
    final total = uniqueUrls.length;
    if (total == 0) {
      onProgress?.call(0, 0);
      return {};
    }

    var completed = 0;
    final outcomes = await runWithConcurrency<String, ImageDownloadOutcome>(
      uniqueUrls,
      maxConcurrent: maxConcurrent,
      task: (url) async {
        final outcome = await _downloadAndSaveImage(
          url,
          storageDirectory: storageDirectory,
          skipIfHostCoolingDown: skipIfHostCoolingDown,
        );
        completed++;
        onProgress?.call(completed, total);
        return outcome;
      },
    );
    return Map.fromIterables(uniqueUrls, outcomes);
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
    final appDir = await _store.documentsDirectory();
    final dir = Directory(p.join(appDir.path, 'deck_covers'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<ImageDownloadOutcome> _downloadAndSaveImage(
    String url, {
    required String storageDirectory,
    required bool skipIfHostCoolingDown,
  }) async {
    final existingPath = await _store.existingPathFor(
      url,
      storageDirectory: storageDirectory,
    );
    if (existingPath != null) {
      _log.debug('Reusing cached image for $url at $existingPath');
      return ImageSaved(existingPath);
    }

    final source = Uri.parse(url);
    final outcome = await _fetchAndSave(
      url,
      from: source,
      storageDirectory: storageDirectory,
      skipIfHostCoolingDown: skipIfHostCoolingDown,
    );
    final fallbackHost = imageHostFallbacks[source.host];
    if (outcome is! ImageHostProblem || fallbackHost == null) return outcome;

    _log.debug('Retrying $url from fallback host $fallbackHost');
    final fallbackOutcome = await _fetchAndSave(
      url,
      from: source.replace(host: fallbackHost),
      storageDirectory: storageDirectory,
      skipIfHostCoolingDown: skipIfHostCoolingDown,
    );
    // A failed mirror says nothing new: the problem to report is still the
    // one with the host the URL names.
    return fallbackOutcome is ImageSaved ? fallbackOutcome : outcome;
  }

  /// Downloads [from] and saves it as the cached copy of [url] — the two
  /// differ when [from] is on a fallback host (see [imageHostFallbacks] for
  /// why the copy is still filed under [url]).
  Future<ImageDownloadOutcome> _fetchAndSave(
    String url, {
    required Uri from,
    required String storageDirectory,
    required bool skipIfHostCoolingDown,
  }) async {
    if (skipIfHostCoolingDown &&
        _hostCooldownTracker.cooldownForHost(from.host) != null) {
      _log.debug('Skipping $from: host is cooling down');
      return ImageHostUnreachable(from.host);
    }

    File? tempFile;
    try {
      final filePath = await _store.pathFor(
        url,
        storageDirectory: storageDirectory,
      );
      final subDirectory = File(filePath).parent;
      if (!subDirectory.existsSync()) {
        subDirectory.createSync(recursive: true);
      }
      final file = File(filePath);
      tempFile = File('$filePath.part');

      _log.debug(
        'Downloading reference image from $from into $storageDirectory',
      );
      final responseBytes = await _downloadBytes(
        from,
        timeout: _referenceImageTimeout,
      );
      await tempFile.writeAsBytes(responseBytes);
      await tempFile.rename(file.path);
      return ImageSaved(file.path);
    } catch (e) {
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
      _log.warn(e.toString());
      return _outcomeOfFailure(e, host: from.host);
    }
  }

  static ImageDownloadOutcome _outcomeOfFailure(
    Object error, {
    required String host,
  }) => switch (error) {
    HttpDownloadException(statusCode: 403) => ImageHostRefused(host),
    HttpDownloadException(:final statusCode)
        when statusCode >= 400 &&
            statusCode < 500 &&
            !_hostSideClientErrors.contains(statusCode) =>
      ImageNotFound(host, statusCode),
    HttpDownloadException() ||
    TimeoutException() ||
    http.ClientException() ||
    SocketException() ||
    TlsException() => ImageHostUnreachable(host),
    _ => const ImageLocalFailure(),
  };

  Future<List<int>> _downloadBytes(Uri url, {required Duration timeout}) async {
    final response = await _client
        .get(url)
        .timeout(
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
}

final class HttpDownloadException implements Exception {
  final Uri url;
  final int statusCode;

  const HttpDownloadException(this.url, this.statusCode);

  bool get isRetryable => statusCode == 429 || statusCode >= 500;

  @override
  String toString() => 'Download failed ($statusCode) for $url';
}
