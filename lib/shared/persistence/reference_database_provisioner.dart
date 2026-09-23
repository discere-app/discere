import 'dart:async';
import 'dart:io';

import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/persistence/reference_db_downloader.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
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

  static const String _fileName = 'discere_reference.db';
  static const String prefKeyVersion = 'reference_db_version';
  static const String prefKeySchemaVersion = 'reference_db_schema_version';

  /// Reference-DB schema version this app build's SQL (see
  /// `lib/catalog/repository/`) is written against. A manifest advertising a
  /// different `schemaVersion` is rejected rather than installed — an older
  /// app version silently accepting a newer, incompatible schema would fail
  /// later with missing/renamed tables or columns instead of a clear error.
  /// Bump only in lockstep with a schema change in `etl/core/sql/schema.sql`
  /// and the matching query changes in `lib/catalog/repository/`.
  @visibleForTesting
  static const int supportedSchemaVersion = 1;

  final ReferenceDbDownloader _downloader;
  final NetworkAvailability _networkAvailability;

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
    required ReferenceDbDownloader downloader,
    required NetworkAvailability networkAvailability,
  }) : _downloader = downloader,
       _networkAvailability = networkAvailability;

  static Future<String> resolveLocalPath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, _fileName);
  }

  /// The currently-installed reference-DB version, or null if none has ever
  /// been installed. A static, network-free accessor — unlike [currentStatus],
  /// this only reads the stamped [prefKeyVersion] pref, so callers that just
  /// need the version (e.g. `BaseWorker` stamping it onto a capability row)
  /// don't need to depend on a full [ReferenceDatabaseProvisioner] instance
  /// (with its http client / keepalive wiring).
  static Future<int?> currentVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(prefKeyVersion);
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
    await _downloader.downloadAndInstall(
      info._manifest,
      await resolveLocalPath(),
      onProgress: onProgress,
    );
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
    final manifest = await _downloader.fetchManifest();

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

  Future<void> _stampInstalled(ReferenceDbManifest manifest) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(prefKeyVersion, manifest.version);
    await prefs.setInt(prefKeySchemaVersion, manifest.schemaVersion);
    _log.debug(
      'Reference database installed (version ${manifest.version}).',
    );
  }

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
  final ReferenceDbManifest _manifest;

  const ReferenceDbUpdateInfo._(this._manifest);

  int get version => _manifest.version;
  int get compressedSizeBytes => _manifest.compressedSizeBytes;
}
