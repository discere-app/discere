import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/image_download_outcome.dart';
import 'package:discere/shared/service/image_host_fallbacks.dart';
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

  /// The 4xx statuses that describe the host's state rather than the
  /// requested image: timed out waiting, too early, too many requests.
  static const _hostSideClientErrors = {408, 425, 429};

  final http.Client _client;
  final HostCooldownTracker _hostCooldownTracker;

  /// The app documents directory, resolved at most once per instance. It is
  /// fixed for the process lifetime but reached over a platform channel, and
  /// a bulk resolve asks for hundreds of paths in a row — one round trip for
  /// all of them instead of one per path. An instance field rather than a
  /// static one, so a test that swaps path_provider's implementation gets the
  /// directory that test installed.
  Future<Directory>? _documentsDirectory;

  ImageService({
    required http.Client client,
    required HostCooldownTracker hostCooldownTracker,
  }) : _client = client,
       _hostCooldownTracker = hostCooldownTracker;

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

  Future<Directory> _resolveDocumentsDirectory() async {
    final pending = _documentsDirectory ??= getApplicationDocumentsDirectory();
    try {
      return await pending;
    } catch (_) {
      // Only a successful lookup is worth remembering. This service is a
      // singleton, so a remembered failure would leave every image path in the
      // app unresolvable for the rest of the run; dropping it lets the next
      // caller try the channel again.
      if (_documentsDirectory == pending) _documentsDirectory = null;
      rethrow;
    }
  }

  Future<Directory> _getCoverImageDir() async {
    final appDir = await _resolveDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'deck_covers'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<ImageDownloadOutcome> _downloadAndSaveImage(
    String url, {
    required String storageDirectory,
    required bool skipIfHostCoolingDown,
  }) async {
    final existingPath = await _resolveExistingImagePath(
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
      final filePath = await _buildLocalImagePath(
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

  Future<String?> _resolveExistingImagePath(
    String url, {
    required String storageDirectory,
    Set<String> legacyDirectories = const {},
  }) async {
    final documents = await _resolveDocumentsDirectory();
    final name = _cachedImageNameFor(url);

    for (final directory in {storageDirectory, ...legacyDirectories}) {
      final path = _cachedImagePath(documents, directory, name);
      if (await File(path).exists()) {
        return path;
      }
    }

    return null;
  }

  Future<String> _buildLocalImagePath(
    String url, {
    required String storageDirectory,
  }) async => _cachedImagePath(
    await _resolveDocumentsDirectory(),
    storageDirectory,
    _cachedImageNameFor(url),
  );

  /// Where a URL's cached copy is named: a collision-safe file name (the URL's
  /// MD5, keeping its extension) inside a per-host folder. Derived once per
  /// URL so that looking through several storage directories for the same URL
  /// doesn't parse and hash it again for each one.
  _CachedImageName _cachedImageNameFor(String url) {
    final uri = Uri.parse(url);
    final urlHash = md5.convert(utf8.encode(url)).toString();
    final ext = p.extension(uri.path);
    return (
      hostFolder: uri.host.replaceAll('.', '_'),
      fileName: '$urlHash${ext.isNotEmpty ? ext : '.jpg'}',
    );
  }

  String _cachedImagePath(
    Directory documents,
    String storageDirectory,
    _CachedImageName name,
  ) => p.join(
    documents.path,
    storageDirectory,
    name.hostFolder,
    name.fileName,
  );
}

typedef _CachedImageName = ({String hostFolder, String fileName});

final class HttpDownloadException implements Exception {
  final Uri url;
  final int statusCode;

  const HttpDownloadException(this.url, this.statusCode);

  bool get isRetryable => statusCode == 429 || statusCode >= 500;

  @override
  String toString() => 'Download failed ($statusCode) for $url';
}
