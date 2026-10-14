import 'package:discere/shared/persistence/reference_id/reference_alias_map.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_rewrite_report.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_tables.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Brings the reference IDs in the user's data in line with the installed
/// reference database, by applying its `entity_aliases`.
///
/// A release of the reference database may supersede IDs — when two entities
/// turn out to be one, or when the ID scheme itself changes — and records
/// each superseded ID as an alias of the one that replaces it. Learning
/// progress, enrichment state and caches in the user database, and the ID
/// lists kept in preferences (the watchlist), still hold the IDs they were
/// written with; this rewrites them, with the collision rules of
/// [referenceIdTables] for rows that become one.
///
/// Must run before anything reads or writes those IDs — the bootstrap runs
/// it once the reference database is in place and before it builds any
/// service. Nothing that writes learning progress or deck membership runs
/// meanwhile, which is why the IDs are collected before the transaction
/// rather than inside it. After an in-app restart, work of the ended
/// session that nobody counted may still write cache rows under the old IDs
/// (iNaturalist metadata, search enrichment). Those are caches: a row under
/// an old ID is never read again, and the valid ID's is filled anew.
///
/// Safe to repeat and to interrupt:
/// - Rewriting is idempotent: a rewritten ID is never an alias, so a second
///   run finds nothing to do.
/// - The table rewrites share one transaction; a failure rolls all of them
///   back and propagates, and the run is not recorded as done.
/// - Which reference-database version the aliases were applied for is
///   recorded under [prefKeyAppliedVersion] only after everything else
///   succeeded. A crash before that just means the next start runs again.
class ReferenceIdMigration {
  static final _log = Logger.forType(ReferenceIdMigration);

  /// The reference-database version whose aliases the user's data was last
  /// brought in line with.
  static const prefKeyAppliedVersion = 'reference_id_aliases_applied_version';

  ReferenceIdMigration({
    required Database userDb,
    required DatabaseExecutor referenceDb,
    required SharedPreferences preferences,
    required Set<String> idListPreferenceKeys,
  }) : _userDb = userDb,
       _referenceDb = referenceDb,
       _preferences = preferences,
       _idListPreferenceKeys = idListPreferenceKeys;

  final Database _userDb;
  final DatabaseExecutor _referenceDb;
  final SharedPreferences _preferences;

  /// Preference keys holding string lists of reference IDs.
  final Set<String> _idListPreferenceKeys;

  /// Applies the aliases of the reference database at [installedVersion],
  /// unless they already were. Returns what was rewritten, or null when
  /// nothing had to run.
  Future<ReferenceIdRewriteReport?> applyIfNeeded({
    required int installedVersion,
  }) async {
    if (_preferences.getInt(prefKeyAppliedVersion) == installedVersion) {
      return null;
    }
    final stopwatch = Stopwatch()..start();

    final referencedIds = {
      ...await collectReferencedIds(_userDb),
      for (final key in _idListPreferenceKeys)
        ...?_preferences.getStringList(key),
    };
    final aliases = await ReferenceAliasMap.load(_referenceDb, referencedIds);
    final report = ReferenceIdRewriteReport();

    if (!aliases.isEmpty) {
      // Before the transaction: a preference write cannot be rolled back
      // with it. Rewriting the lists is idempotent, and correct for the
      // installed database whether or not the tables follow.
      await _rewritePreferenceLists(aliases, report);
      await _userDb.transaction((txn) async {
        await aliases.writeTempTable(txn);
        for (final table in referenceIdTables) {
          await table.rewrite(txn, report);
        }
        await rewriteSearchDocumentEntityIds(txn, report);
        await ReferenceAliasMap.dropTempTable(txn);
      });
    }

    await _preferences.setInt(prefKeyAppliedVersion, installedVersion);
    final summary =
        'Reference IDs applied for reference database $installedVersion '
        '(${referencedIds.length} referenced, '
        '${aliases.newIdByAlias.length} aliased, '
        '${stopwatch.elapsedMilliseconds}ms): $report';
    // Rows dropped in a merge are user data gone for good; that goes to the
    // persisted diagnostics, a plain rename does not.
    if (report.totalDropped > 0) {
      _log.warn(summary);
    } else {
      _log.info(summary);
    }
    return report;
  }

  Future<void> _rewritePreferenceLists(
    ReferenceAliasMap aliases,
    ReferenceIdRewriteReport report,
  ) async {
    for (final key in _idListPreferenceKeys) {
      final ids = _preferences.getStringList(key);
      if (ids == null) continue;
      final rewritten = ids.where((id) => aliases.rewrite(id) != id).length;
      if (rewritten == 0) continue;
      final unique = {for (final id in ids) aliases.rewrite(id)}.toList();
      await _preferences.setStringList(key, unique);
      report.record(
        'preference $key',
        rewritten: rewritten,
        dropped: ids.length - unique.length,
      );
    }
  }
}
