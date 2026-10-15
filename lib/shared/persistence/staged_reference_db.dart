import 'dart:convert';
import 'dart:io';

/// A downloaded, checksum-verified reference database waiting next to the
/// active one until the bootstrap puts it in place.
///
/// A running session keeps the active file open, so an update found during a
/// session is never written over it; it is staged here instead. Two files
/// make up a staged update: the database at [filePath], and a small metadata
/// file beside it with the manifest's version and schema version, written
/// only once the database is complete. Their combination says how far a
/// staging or an installation got:
///
/// - database and metadata — staged, waiting to be installed;
/// - database without metadata — a staging that never finished, to discard;
/// - metadata without database — an installation that renamed the database
///   into place and stopped before it was recorded as installed.
class StagedReferenceDb {
  StagedReferenceDb(this.activePath);

  /// Where the active reference database lives.
  final String activePath;

  String get filePath => '$activePath.pending';
  String get _metadataPath => '$activePath.pending.json';

  Future<bool> get hasFile => File(filePath).exists();

  /// Records [version] and [schemaVersion] for the database at [filePath],
  /// which is complete by now. Written to a temporary file and renamed, so a
  /// crash never leaves half a metadata file behind.
  Future<void> writeMetadata({
    required int version,
    required int schemaVersion,
  }) async {
    final temporary = File('$_metadataPath.part');
    await temporary.writeAsString(
      jsonEncode({'version': version, 'schemaVersion': schemaVersion}),
      flush: true,
    );
    await temporary.rename(_metadataPath);
  }

  /// The staged version and schema version, or null when no metadata is
  /// there or it cannot be read.
  Future<({int version, int schemaVersion})?> readMetadata() async {
    final file = File(_metadataPath);
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as Map;
      return (
        version: json['version'] as int,
        schemaVersion: json['schemaVersion'] as int,
      );
    } on Object {
      return null;
    }
  }

  /// Moves the staged database over the active one. A rename within one
  /// directory: the active path holds either the old file or the new one.
  Future<void> moveIntoPlace() => File(filePath).rename(activePath);

  /// Removes everything a staging left behind. The metadata goes first, so
  /// an interruption leaves at worst a database without metadata — which
  /// counts as unfinished and is removed by the next call.
  Future<void> clear() async {
    for (final path in [
      _metadataPath,
      '$_metadataPath.part',
      filePath,
      '$filePath.part',
      '$filePath.gz.part',
    ]) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }
}

/// Removes the files SQLite keeps beside the database at [databasePath]:
/// the write-ahead log and its index (`-wal`, `-shm`), and the rollback
/// journal (`-journal`).
///
/// For right after a new file was renamed over [databasePath], before
/// anything opens it. Releases are built in WAL mode, so opening one leaves
/// `-wal` and `-shm` behind. The app opens the reference database read-only,
/// so that log stays empty and does no harm over a new file. It is removed
/// anyway: SQLite does not tie a write-ahead log to its database file, so
/// one holding frames — from whatever writer — would be read as part of the
/// new database, and no test would notice.
Future<void> deleteJournalFiles(String databasePath) async {
  for (final suffix in const ['-wal', '-shm', '-journal']) {
    final file = File('$databasePath$suffix');
    if (await file.exists()) await file.delete();
  }
}
