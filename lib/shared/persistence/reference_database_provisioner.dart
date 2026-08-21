import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/service/foreground_service_keeper.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Downloads and installs the reference species database at runtime, keeping
/// it out of the app bundle. The download target (a small `manifest.json`
/// describing version, schema version, download URL and checksum) is hosted
/// externally so the actual hosting platform can change without touching this
/// class — see https://github.com/discere-app/discere/issues/54.
///
/// A [ChangeNotifier] so UI (the update-confirmation dialog on the main
/// screen) can react to [pendingUpdate] without polling.
class ReferenceDatabaseProvisioner extends ChangeNotifier {
  static final _log = Logger.forType(ReferenceDatabaseProvisioner);

  static const String _manifestUrl = AppConstants.referenceDbManifestUrl;
  static const String _fileName = 'discere_reference.db';
  static const String prefKeyVersion = 'reference_db_version';
  static const String prefKeySchemaVersion = 'reference_db_schema_version';
  static const Duration _manifestTimeout = Duration(seconds: 10);
  // Bounds only getting the response (headers) — the body can legitimately
  // take much longer to stream for a large file on a slow connection.
  static const Duration _downloadTimeout = Duration(minutes: 15);
  // Bounds stalls while streaming the body: resets on every chunk received,
  // so a slow-but-progressing download never hits this, but a connection
  // that stops delivering bytes entirely doesn't hang forever either.
  static const Duration _downloadIdleTimeout = Duration(seconds: 30);

  /// Reference-DB schema version this app build's SQL (see
  /// `lib/catalog/repository/`) is written against. A manifest advertising a
  /// different `schemaVersion` is rejected rather than installed — an older
  /// app version silently accepting a newer, incompatible schema would fail
  /// later with missing/renamed tables or columns instead of a clear error.
  /// Bump only in lockstep with a schema change in `etl/core/sql/schema.sql`
  /// and the matching query changes in `lib/catalog/repository/`.
  @visibleForTesting
  static const int supportedSchemaVersion = 1;

  final http.Client _client;
  final NetworkAvailability _networkAvailability;
  final ForegroundServiceKeeper _foregroundServiceKeeper;

  ReferenceDbUpdateInfo? _pendingUpdate;
  bool _pendingUpdateOnWifi = false;

  /// A newer reference-DB version is available. Set by
  /// [ensureUpToDateInBackground] whenever the manifest reports a newer
  /// version than what's installed — regardless of network type, since even
  /// a ~90MB Wi-Fi download deserves the user's explicit consent rather than
  /// installing unannounced. Cleared by [dismissPendingUpdate] or once
  /// [downloadAndInstall] succeeds; dismissal isn't persisted, so a still-
  /// newer version is re-surfaced the next time the app starts.
  ReferenceDbUpdateInfo? get pendingUpdate => _pendingUpdate;

  /// Whether [pendingUpdate] was detected while on Wi-Fi — drives whether
  /// the confirmation dialog shows the cellular-data warning line.
  bool get pendingUpdateOnWifi => _pendingUpdateOnWifi;

  ReferenceDatabaseProvisioner({
    required http.Client client,
    required NetworkAvailability networkAvailability,
    required ForegroundServiceKeeper foregroundServiceKeeper,
  }) : _client = client,
       _networkAvailability = networkAvailability,
       _foregroundServiceKeeper = foregroundServiceKeeper;

  static Future<String> resolveLocalPath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, _fileName);
  }

  /// Read-only snapshot of the locally installed reference database, for the
  /// diagnostics page. Reads only already-persisted state (the version
  /// numbers stamped by [_stampInstalled], the file itself) — never
  /// touches the network.
  Future<ReferenceDbStatus> currentStatus() async {
    final path = await resolveLocalPath();
    final file = File(path);
    final exists = await file.exists();
    final prefs = await SharedPreferences.getInstance();
    return ReferenceDbStatus(
      installedVersion: prefs.getInt(prefKeyVersion),
      installedSchemaVersion: prefs.getInt(prefKeySchemaVersion),
      supportedSchemaVersion: supportedSchemaVersion,
      fileExists: exists,
      fileSizeBytes: exists ? await file.length() : null,
      fileModifiedAt: exists ? (await file.stat()).modified : null,
    );
  }

  /// Whether a local copy exists **and** is schema-compatible with this app
  /// build. A file that exists but was installed under an older,
  /// since-bumped schema is not usable — opening it would let repositories
  /// query missing/renamed tables or columns instead of failing clearly up
  /// front, so the caller should run the blocking download path instead of
  /// the instant-start fast path even though a file is present.
  Future<bool> hasUsableLocalCopy() async {
    final path = await resolveLocalPath();
    if (!await File(path).exists()) return false;

    final prefs = await SharedPreferences.getInstance();
    final storedSchemaVersion = prefs.getInt(prefKeySchemaVersion);
    if (storedSchemaVersion == null) {
      // Pre-existing file from before schema-version tracking existed (the
      // old bundled-asset mechanism used this same path). Its actual schema
      // matches this baseline release, so stamp it now rather than forcing
      // an unnecessary re-download — future schema bumps are then correctly
      // detected from this point on.
      await prefs.setInt(prefKeySchemaVersion, supportedSchemaVersion);
      return true;
    }
    return storedSchemaVersion == supportedSchemaVersion;
  }

  /// Best-effort background refresh for the common case where a local copy
  /// already exists. Never throws: a failed manifest check must never take
  /// away an already-usable cached copy (e.g. the user is offline, or the
  /// manifest host is temporarily unreachable).
  ///
  /// Never downloads on its own — a newer version is only surfaced via
  /// [pendingUpdate] for the UI to confirm explicitly (see
  /// [downloadPendingUpdate]), on Wi-Fi or cellular alike.
  Future<void> ensureUpToDateInBackground() async {
    try {
      final info = await _resolveUpdate(force: false);
      if (info == null) {
        _setPendingUpdate(null, onWifi: false);
        return;
      }
      final onWifi = await _networkAvailability.isOnWifi();
      _setPendingUpdate(info, onWifi: onWifi);
    } catch (e) {
      _log.warn(
        'Background reference database update check failed, keeping cached copy: $e',
      );
    }
  }

  /// Fetches the manifest and reports whether a download is needed — used by
  /// the blocking first-launch flow, which needs the size before deciding
  /// whether to ask for cellular confirmation. Since there is no local copy
  /// yet in that case, the result is never null. Rethrows on failure so the
  /// caller can show a retry UI.
  Future<ReferenceDbUpdateInfo> checkForUpdate() async {
    return (await _resolveUpdate(force: true))!;
  }

  /// Downloads and installs an update previously returned by
  /// [checkForUpdate] or found via [pendingUpdate]. Rethrows on failure so
  /// the caller can show a retry UI.
  Future<void> downloadAndInstall(
    ReferenceDbUpdateInfo info, {
    required void Function(double progress)? onProgress,
  }) async {
    await _downloadAndInstall(info._manifest, onProgress: onProgress);
    await _stampInstalled(info._manifest);
    _setPendingUpdate(null, onWifi: false);
  }

  /// Confirms and installs [pendingUpdate]. No-op if nothing is pending.
  /// Rethrows on failure so the caller can show an error — the pending
  /// update is left in place so a retry is possible.
  Future<void> downloadPendingUpdate() async {
    final info = _pendingUpdate;
    if (info == null) return;
    await downloadAndInstall(info, onProgress: null);
  }

  /// Declines [pendingUpdate] for the rest of this app session without
  /// downloading it. Re-evaluated (and re-shown if still newer) on the next
  /// [ensureUpToDateInBackground] call, i.e. the next app start.
  void dismissPendingUpdate() {
    _setPendingUpdate(null, onWifi: false);
  }

  /// Test-only seam for simulating a background update check having found a
  /// newer version, without driving a real manifest fetch — used by
  /// integration tests, where all real HTTP is forced to fail fast (see
  /// integration_test/test_utils.dart's `_FastFailHttpOverrides`).
  @visibleForTesting
  void debugSetPendingUpdateForTest(int version, {bool onWifi = true}) {
    _setPendingUpdate(
      ReferenceDbUpdateInfo._(
        _ReferenceDbManifest(
          version: version,
          schemaVersion: supportedSchemaVersion,
          url: '',
          sha256: '',
          compressedSizeBytes: 0,
        ),
      ),
      onWifi: onWifi,
    );
  }

  void _setPendingUpdate(ReferenceDbUpdateInfo? info, {required bool onWifi}) {
    if (_pendingUpdate?.version == info?.version &&
        _pendingUpdateOnWifi == onWifi) {
      return;
    }
    _pendingUpdate = info;
    _pendingUpdateOnWifi = onWifi;
    notifyListeners();
  }

  Future<ReferenceDbUpdateInfo?> _resolveUpdate({required bool force}) async {
    final manifest = await _fetchManifest();

    if (manifest.schemaVersion != supportedSchemaVersion) {
      throw DataFormatException(
        'Reference database schema version ${manifest.schemaVersion} is not '
        'supported by this app build (expects $supportedSchemaVersion). '
        'Update the app to receive this reference database.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final localVersion = prefs.getInt(prefKeyVersion) ?? 0;

    if (!force && manifest.version <= localVersion) {
      _log.debug('Reference database is up to date (version $localVersion).');
      return null;
    }

    return ReferenceDbUpdateInfo._(manifest);
  }

  Future<void> _stampInstalled(_ReferenceDbManifest manifest) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(prefKeyVersion, manifest.version);
    await prefs.setInt(prefKeySchemaVersion, manifest.schemaVersion);
    _log.debug(
      'Reference database installed (version ${manifest.version}).',
    );
  }

  Future<_ReferenceDbManifest> _fetchManifest() async {
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

      return _ReferenceDbManifest.fromJson(
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
  Future<void> _downloadAndInstall(
    _ReferenceDbManifest manifest, {
    required void Function(double progress)? onProgress,
  }) async {
    await _foregroundServiceKeeper.startKeepingAlive();
    try {
      await _downloadAndInstallImpl(manifest, onProgress: onProgress);
    } finally {
      unawaited(_foregroundServiceKeeper.stopKeepingAlive());
    }
  }

  Future<void> _downloadAndInstallImpl(
    _ReferenceDbManifest manifest, {
    required void Function(double progress)? onProgress,
  }) async {
    final path = await resolveLocalPath();
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

class ReferenceDbStatus {
  final int? installedVersion;
  final int? installedSchemaVersion;
  final int supportedSchemaVersion;
  final bool fileExists;
  final int? fileSizeBytes;
  final DateTime? fileModifiedAt;

  const ReferenceDbStatus({
    required this.installedVersion,
    required this.installedSchemaVersion,
    required this.supportedSchemaVersion,
    required this.fileExists,
    required this.fileSizeBytes,
    required this.fileModifiedAt,
  });
}

/// A pending or available reference-DB update, as advertised by the
/// manifest, with just enough surfaced for UI (size, version) — the actual
/// download URL/checksum stay private to [ReferenceDatabaseProvisioner].
class ReferenceDbUpdateInfo {
  final _ReferenceDbManifest _manifest;

  const ReferenceDbUpdateInfo._(this._manifest);

  int get version => _manifest.version;
  int get compressedSizeBytes => _manifest.compressedSizeBytes;
}

class _ReferenceDbManifest {
  final int version;
  final int schemaVersion;
  final String url;
  final String sha256;
  final int compressedSizeBytes;

  const _ReferenceDbManifest({
    required this.version,
    required this.schemaVersion,
    required this.url,
    required this.sha256,
    required this.compressedSizeBytes,
  });

  factory _ReferenceDbManifest.fromJson(Map<String, dynamic> json) {
    return _ReferenceDbManifest(
      version: json['version'] as int,
      schemaVersion: json['schemaVersion'] as int,
      url: json['url'] as String,
      sha256: json['sha256'] as String,
      compressedSizeBytes: json['compressedSizeBytes'] as int? ?? 0,
    );
  }
}
