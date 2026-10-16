import 'dart:async';
import 'dart:io';

import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/persistence/reference_db_downloader.dart';
import 'package:discere/shared/persistence/reference_db_manifest.dart';
import 'package:discere/shared/persistence/staged_reference_db.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Downloads and installs the reference species database at runtime, keeping
/// it out of the app bundle. The download target (a small `manifest.json`
/// listing the published releases, each with version, schema version,
/// download URL and checksum) is hosted externally so the actual hosting platform can change without touching this
/// class — see https://github.com/discere-app/discere/issues/54.
///
/// Works on files and the stamped versions only. What a session knows and
/// does about an update — found, declined, downloading, staged — is
/// `ReferenceDbUpdateService`'s, which uses [findNewerVersion] and [stage].
class ReferenceDatabaseProvisioner {
  static final _log = Logger.forType(ReferenceDatabaseProvisioner);

  static const String _fileName = 'discere_reference.db';
  static const String prefKeyVersion = 'reference_db_version';
  static const String prefKeySchemaVersion = 'reference_db_schema_version';

  /// Reference-DB schema versions this app build's SQL (see
  /// `lib/catalog/repository/`) works with. Of the releases the manifest
  /// offers, only one of these schemas is installed — an app silently
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

  /// Closes the app's database connections (`DatabaseHelper.close`), run
  /// right after a new file was renamed over the active one. sqflite keeps a
  /// connection per path, and one opened before the rename — by work of a
  /// session that just ended — keeps reading the replaced file under the
  /// same path; the next open would be handed that connection.
  final Future<void> Function() _closeOpenDatabases;

  bool _installedThisStart = false;

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
    required Future<void> Function() closeOpenDatabases,
  }) : _downloader = downloader,
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
  /// numbers stamped by [_stamp], the file itself) — never
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

  /// The newest release this build can read, when it is newer than the
  /// installed one, or null when it is not. Throws when the manifest cannot
  /// be fetched or offers no release of a schema this build supports.
  Future<ReferenceDbUpdateInfo?> findNewerVersion() =>
      _resolveUpdate(force: false);

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
      info._release,
      path,
      onProgress: onProgress,
    );
    await _closeOpenDatabases();
    await deleteJournalFiles(path);
    await _stamp(info._release.version, info._release.schemaVersion);
  }

  /// Downloads [info] and stages it next to the active file — the running
  /// session keeps reading the database it has open, and nothing is
  /// stamped yet. [installStagedUpdate] puts it in place on the next
  /// bootstrap. Rethrows on failure; a half-written staging is discarded by
  /// the next attempt or the next start.
  Future<void> stage(
    ReferenceDbUpdateInfo info, {
    required void Function(double progress)? onProgress,
  }) async {
    final staged = StagedReferenceDb(await resolveLocalPath());
    await staged.clear();
    await _downloader.downloadAndInstall(
      info._release,
      staged.filePath,
      onProgress: onProgress,
    );
    await staged.writeMetadata(
      version: info.version,
      schemaVersion: info._release.schemaVersion,
    );
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

  Future<ReferenceDbUpdateInfo?> _resolveUpdate({required bool force}) async {
    final manifest = await _downloader.fetchManifest();
    final release = manifest.newestReadable(supportedSchemaVersions);

    if (release == null) {
      throw DataFormatException(
        'The reference database manifest offers schema versions '
        '${manifest.schemaVersions.join(', ')}, none supported by this app '
        'build (supports ${supportedSchemaVersions.join(', ')}). '
        'Update the app to receive a reference database.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final localVersion = prefs.getInt(prefKeyVersion) ?? 0;

    if (!force && release.version <= localVersion) {
      _log.debug('Reference database is up to date (version $localVersion).');
      return null;
    }

    return ReferenceDbUpdateInfo._(release);
  }

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

/// A pending or available reference-DB update — the release of the manifest
/// this build chose — with just enough surfaced for UI (size, version); the
/// actual download URL/checksum stay private to
/// [ReferenceDatabaseProvisioner].
class ReferenceDbUpdateInfo {
  final ReferenceDbRelease _release;

  const ReferenceDbUpdateInfo._(this._release);

  @visibleForTesting
  const ReferenceDbUpdateInfo.ofRelease(this._release);

  int get version => _release.version;
  int get compressedSizeBytes => _release.compressedSizeBytes;
}
