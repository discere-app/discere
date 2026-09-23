import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/service/foreground_service_keeper.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:http/http.dart' as http;

/// Fetches the reference-database manifest and installs the file it points
/// at: HTTP, gzip, SHA-256, filesystem, and nothing else.
///
/// Split out of [ReferenceDatabaseProvisioner] so the part that decides
/// *whether* to download — version comparison, Wi-Fi gating, the pending
/// update the UI reacts to — can be tested without real network or real
/// files, which is where that logic previously hid.
class ReferenceDbDownloader {
  static final _log = Logger.forType(ReferenceDbDownloader);

  static const String _manifestUrl = AppConstants.referenceDbManifestUrl;
  static const Duration _manifestTimeout = Duration(seconds: 10);
  // Bounds only getting the response (headers) — the body can legitimately
  // take much longer to stream for a large file on a slow connection.
  static const Duration _downloadTimeout = Duration(minutes: 15);
  // Bounds stalls while streaming the body: resets on every chunk received,
  // so a slow-but-progressing download never hits this, but a connection
  // that stops delivering bytes entirely doesn't hang forever either.
  static const Duration _downloadIdleTimeout = Duration(seconds: 30);

  final http.Client _client;
  final ForegroundServiceKeeper _foregroundServiceKeeper;

  const ReferenceDbDownloader({
    required http.Client client,
    required ForegroundServiceKeeper foregroundServiceKeeper,
  }) : _client = client,
       _foregroundServiceKeeper = foregroundServiceKeeper;

  /// Fetches and parses the manifest describing the newest published
  /// reference database. Throws rather than returning null: a caller that
  /// cannot reach the manifest has no basis for any decision.
  Future<ReferenceDbManifest> fetchManifest() async {
    try {
      final response = await _client
          .get(Uri.parse(_manifestUrl))
          .timeout(_manifestTimeout);

      if (response.statusCode != 200) {
        throw ServerException(
          'Failed to fetch reference database manifest.',
          statusCode: response.statusCode,
        );
      }

      return ReferenceDbManifest.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on TimeoutException {
      throw NetworkException('Reference database manifest request timed out.');
    } on SocketException catch (e) {
      throw NetworkException(
        'No internet connection while checking for reference database updates.',
        originalError: e,
      );
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Network connection failed while checking for reference database updates.',
        originalError: e,
      );
    } on FormatException catch (e) {
      throw DataFormatException(
        'Invalid reference database manifest format.',
        originalError: e,
      );
    }
  }

  // Keeps the process alive (Android foreground service) for the duration of
  // the download — without it the OS may reap the process if the app is
  // backgrounded mid-download, silently stalling a transfer that can take
  // minutes on a slow connection. No-op on platforms without a keepalive
  // mechanism (iOS, desktop) — see
  // https://github.com/discere-app/discere/issues/101.
  Future<void> downloadAndInstall(
    ReferenceDbManifest manifest,
    String destinationPath, {
    required void Function(double progress)? onProgress,
  }) async {
    await _foregroundServiceKeeper.startKeepingAlive();
    try {
      await _downloadAndInstallImpl(manifest, destinationPath, onProgress: onProgress);
    } finally {
      unawaited(_foregroundServiceKeeper.stopKeepingAlive());
    }
  }

  Future<void> _downloadAndInstallImpl(
    ReferenceDbManifest manifest,
    String path, {
    required void Function(double progress)? onProgress,
  }) async {
    final compressedPart = File('$path.gz.part');
    final decompressedPart = File('$path.part');

    _log.debug(
      'Downloading reference database version ${manifest.version} from ${manifest.url}',
    );

    http.StreamedResponse response;
    try {
      response = await _client
          .send(http.Request('GET', Uri.parse(manifest.url)))
          .timeout(_downloadTimeout);
    } on TimeoutException {
      throw NetworkException('Reference database download timed out.');
    } on SocketException catch (e) {
      throw NetworkException(
        'No internet connection while downloading the reference database.',
        originalError: e,
      );
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Network connection failed while downloading the reference database.',
        originalError: e,
      );
    }

    if (response.statusCode != 200) {
      throw ServerException(
        'Failed to download reference database.',
        statusCode: response.statusCode,
      );
    }

    final total = response.contentLength ?? manifest.compressedSizeBytes;
    var received = 0;
    final digestSink = _DigestSink();
    final hashSink = sha256.startChunkedConversion(digestSink);
    final sink = compressedPart.openWrite();

    try {
      await for (final chunk in response.stream.timeout(_downloadIdleTimeout)) {
        sink.add(chunk);
        hashSink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
      await sink.close();
      hashSink.close();
    } catch (e) {
      await sink.close();
      if (await compressedPart.exists()) await compressedPart.delete();
      throw NetworkException(
        'Reference database download was interrupted.',
        originalError: e,
      );
    }

    final actualHash = digestSink.digest.toString();
    if (actualHash != manifest.sha256) {
      await compressedPart.delete();
      throw DataFormatException(
        'Reference database checksum mismatch '
        '(expected ${manifest.sha256}, got $actualHash).',
      );
    }

    // GZIP decompression of a ~200MB file runs in an isolate so it doesn't
    // block the UI, mirroring DeckSerializationWorker's Isolate.run pattern.
    await Isolate.run(
      () => _decompress(compressedPart.path, decompressedPart.path),
    );
    await compressedPart.delete();

    await decompressedPart.rename(path);
  }

  // Streamed rather than reading the whole (~200MB compressed / ~400MB
  // decompressed) file into memory at once, which risked OOMing on
  // memory-constrained devices.
  static Future<void> _decompress(String sourcePath, String destPath) async {
    await File(
      sourcePath,
    ).openRead().transform(gzip.decoder).pipe(File(destPath).openWrite());
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}

  Digest get digest => _digest!;
}

class ReferenceDbManifest {
  final int version;
  final int schemaVersion;
  final String url;
  final String sha256;
  final int compressedSizeBytes;

  const ReferenceDbManifest({
    required this.version,
    required this.schemaVersion,
    required this.url,
    required this.sha256,
    required this.compressedSizeBytes,
  });

  factory ReferenceDbManifest.fromJson(Map<String, dynamic> json) {
    return ReferenceDbManifest(
      version: json['version'] as int,
      schemaVersion: json['schemaVersion'] as int,
      url: json['url'] as String,
      sha256: json['sha256'] as String,
      compressedSizeBytes: json['compressedSizeBytes'] as int? ?? 0,
    );
  }
}
