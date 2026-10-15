import 'dart:async';
import 'dart:io';

import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/persistence/reference_db_downloader.dart';
import 'package:discere/shared/persistence/staged_reference_db.dart';
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

  /// Reference-DB schema versions this app build's SQL (see
  /// `lib/catalog/repository/`) works with. A manifest advertising another
  /// `schemaVersion` is rejected rather than installed — an app silently
  /// accepting a newer, incompatible schema would fail later with
  /// missing/renamed tables or columns instead of a clear error. Extend only
  /// in lockstep with a schema change in `etl/core/sql/schema.sql` and the
  /// matching query changes in `lib/catalog/repository/`.
  ///
  /// - 1: the IDs carry their source; no `entity_aliases`.
  /// - 2: `entity_aliases`, which `ReferenceIdMigration` applies to the user
  ///   database after every change of reference database. An app that
  ///   cannot apply them must not install such a release: its learning
  ///   progress would point at IDs the new database no longer has.
  ///
  /// Both stay supported, so an installed schema-1 copy keeps working and a
  /// schema-2 release arrives through the ordinary staged update rather
  /// than a blocking download.
  static const supportedSchemaVersions = {1, 2};

  /// The schema of a file installed before schema versions were stamped —
  /// the bundled asset of the first releases, which used this same path.
  @visibleForTesting
  static const int unstampedSchemaVersion = 1;

  final ReferenceDbDownloader _downloader;
  final NetworkAvailability _networkAvailability;

  /// Closes the app's database connections (`DatabaseHelper.close`), run
  /// right after a new file was renamed over the active one. sqflite keeps a
  /// connection per path, and one opened before the rename — by work of a
  /// session that just ended — keeps reading the replaced file under the
  /// same path; the next open would be handed that connection.
  final Future<void> Function() _closeOpenDatabases;

  ReferenceDbUpdateInfo? _pendingUpdate;
  bool _pendingUpdateOnWifi = false;
  int? _stagedVersion;
  bool _stagedNoticeDismissed = false;
  bool _installedThisStart = false;

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

  /// An update was downloaded during this session and is staged (see
  /// [StagedReferenceDb]), and the user has not put the notice offering to
  /// apply it aside. Applying it means restarting the app; without that it
  /// is installed on the next start.
  bool get hasStagedUpdateToApply =>
      _stagedVersion != null && !_stagedNoticeDismissed;

  /// The version staged this session, whether or not its notice was put
  /// aside — for the diagnostics page.
  int? get stagedVersion => _stagedVersion;

  /// Puts the notice for the staged update aside for this session. The
  /// update stays staged and is installed on the next start.
  void dismissStagedUpdateNotice() {
    if (_stagedNoticeDismissed) return;
    _stagedNoticeDismissed = true;
    notifyListeners();
  }

  /// Whether this start installed a reference database, and the caller is
  /// the first to ask. For the offer to refresh images resolved against the
  /// previous one, made once after an installation.
  bool takeInstalledThisStart() {
    final installed = _installedThisStart;
    _installedThisStart = false;
    return installed;
  }

  ReferenceDatabaseProvisioner({
    required ReferenceDbDownloader downloader,
    required NetworkAvailability networkAvailability,
    required Future<void> Function() closeOpenDatabases,
  }) : _downloader = downloader,
       _networkAvailability = networkAvailability,
       _closeOpenDatabases = closeOpenDatabases;

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
      supportedSchemaVersions: supportedSchemaVersions,
      fileExists: exists,
      fileSizeBytes: exists ? await file.length() : null,
      fileModifiedAt: exists ? (await file.stat()).modified : null,
    );
  }

  /// Whether a local copy exists **and** is schema-compatible with this app
  /// build. A file installed under a schema this build no longer supports is
  /// not usable — opening it would let repositories query missing/renamed
  /// tables or columns instead of failing clearly up front, so the caller
  /// should run the blocking download path instead of the instant-start fast
  /// path even though a file is present.
  Future<bool> hasUsableLocalCopy() async {
    final path = await resolveLocalPath();
    if (!await File(path).exists()) return false;

    final prefs = await SharedPreferences.getInstance();
    var storedSchemaVersion = prefs.getInt(prefKeySchemaVersion);
    if (storedSchemaVersion == null) {
      // A file without a stamp predates schema-version tracking, so it has
      // the schema of that time. Stamped now, it is judged like any other
      // file from here on — usable while this app build supports that
      // schema.
      storedSchemaVersion = unstampedSchemaVersion;
      await prefs.setInt(prefKeySchemaVersion, storedSchemaVersion);
    }
    return supportedSchemaVersions.contains(storedSchemaVersion);
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

  /// Downloads and installs an update returned by [checkForUpdate] — the
  /// blocking path, taken while nothing has the reference database open.
  /// Rethrows on failure so the caller can show a retry UI.
  Future<void> downloadAndInstall(
    ReferenceDbUpdateInfo info, {
    required void Function(double progress)? onProgress,
  }) async {
    final path = await resolveLocalPath();
    await _downloader.downloadAndInstall(
      info._manifest,
      path,
      onProgress: onProgress,
    );
    await _closeOpenDatabases();
    await deleteJournalFiles(path);
    await _stampInstalled(info._manifest);
    _setPendingUpdate(null, onWifi: false);
  }

  /// Downloads [pendingUpdate] and stages it next to the active file — the
  /// running session keeps reading the database it has open, and nothing is
  /// stamped yet. [installStagedUpdate] puts it in place on the next
  /// bootstrap. No-op if nothing is pending. Rethrows on failure so the
  /// caller can show an error; the pending update is left in place so a
  /// retry is possible.
  Future<void> downloadPendingUpdate() async {
    final info = _pendingUpdate;
    if (info == null) return;
    final staged = StagedReferenceDb(await resolveLocalPath());
    await staged.clear();
    await _downloader.downloadAndInstall(
      info._manifest,
      staged.filePath,
      onProgress: null,
    );
    await staged.writeMetadata(
      version: info.version,
      schemaVersion: info._manifest.schemaVersion,
    );
    _stagedVersion = info.version;
    _stagedNoticeDismissed = false;
    _pendingUpdate = null;
    notifyListeners();
  }

  /// Puts a staged update in place of the active reference database and
  /// stamps it. For the bootstrap, before anything opens that database.
  ///
  /// Never throws for what it finds: a staging that never finished, one
  /// whose schema this build does not support, or one no newer than what is
  /// installed is removed and logged, and the start goes on with the active
  /// file. Resumes an installation an earlier start began: metadata without
  /// a staged file means the file was already moved into place.
  Future<void> installStagedUpdate() async {
    // Whatever this session staged is decided on here, one way or the other.
    _stagedVersion = null;
    final staged = StagedReferenceDb(await resolveLocalPath());
    final metadata = await staged.readMetadata();
    final hasFile = await staged.hasFile;
    if (metadata == null) {
      if (hasFile) _log.warn('Discarding an unfinished reference DB staging');
      await staged.clear();
      return;
    }
    final installed = (await SharedPreferences.getInstance()).getInt(
      prefKeyVersion,
    );
    final reason = !supportedSchemaVersions.contains(metadata.schemaVersion)
        ? 'schema ${metadata.schemaVersion} is not supported'
        : installed != null &&
              (hasFile
                  ? metadata.version <= installed
                  : metadata.version < installed)
        ? 'version ${metadata.version} is not newer than $installed'
        : null;
    if (reason != null) {
      _log.warn('Discarding staged reference DB: $reason');
      await staged.clear();
      return;
    }
    if (hasFile) {
      await staged.moveIntoPlace();
      await _closeOpenDatabases();
    }
    // Also when resuming: a start that stopped after the rename may not have
    // got this far.
    await deleteJournalFiles(staged.activePath);
    await _stamp(metadata.version, metadata.schemaVersion);
    await staged.clear();
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

    if (!supportedSchemaVersions.contains(manifest.schemaVersion)) {
      throw DataFormatException(
        'Reference database schema version ${manifest.schemaVersion} is not '
        'supported by this app build (supports '
        '${supportedSchemaVersions.join(', ')}). '
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

  Future<void> _stampInstalled(ReferenceDbManifest manifest) =>
      _stamp(manifest.version, manifest.schemaVersion);

  Future<void> _stamp(int version, int schemaVersion) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(prefKeyVersion, version);
    await prefs.setInt(prefKeySchemaVersion, schemaVersion);
    _installedThisStart = true;
    _log.debug('Reference database installed (version $version).');
  }

}

class ReferenceDbStatus {
  final int? installedVersion;
  final int? installedSchemaVersion;
  final Set<int> supportedSchemaVersions;
  final bool fileExists;
  final int? fileSizeBytes;
  final DateTime? fileModifiedAt;

  const ReferenceDbStatus({
    required this.installedVersion,
    required this.installedSchemaVersion,
    required this.supportedSchemaVersions,
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
