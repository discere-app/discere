import 'dart:convert';

import 'package:discere/shared/persistence/reference_id/reference_id_rewrite_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The last time the reference IDs of the user's data were brought in line
/// with an installed reference database, and how it ended — kept for the
/// diagnostics page, so a report like "my learning progress is gone" can be
/// traced to whether, and how, the IDs were rewritten.
///
/// One entry, overwritten by every run that does work: what matters when
/// something looks wrong is the run that produced the current state, and a
/// failure after a success is exactly that. A start that skips the run
/// because its version was already applied leaves the entry alone. The
/// error itself goes to the diagnostics log, not here: this is shown to the
/// user, and exception text is not.
///
/// Stored as JSON under [prefKey], independent of whether log entries are
/// persisted. Unreadable content reads as no entry rather than failing the
/// diagnostics page.
sealed class ReferenceIdMigrationRun {
  static const prefKey = 'reference_id_migration_last_run';

  /// The reference-database version the run was for.
  final int referenceDbVersion;
  final DateTime ranAt;

  const ReferenceIdMigrationRun({
    required this.referenceDbVersion,
    required this.ranAt,
  });

  static const _succeeded = 'succeeded';
  static const _failed = 'failed';

  static ReferenceIdMigrationRun? read(SharedPreferences preferences) {
    final raw = preferences.getString(prefKey);
    if (raw == null) return null;
    try {
      return fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(SharedPreferences preferences) =>
      preferences.setString(prefKey, jsonEncode(toJson()));

  /// Throws for content of another shape; [read] turns that into null.
  static ReferenceIdMigrationRun fromJson(Map<String, dynamic> json) {
    final version = json['referenceDbVersion'] as int;
    final ranAt = DateTime.fromMillisecondsSinceEpoch(json['ranAt'] as int);
    return switch (json['outcome']) {
      _succeeded => ReferenceIdMigrationSucceeded(
        referenceDbVersion: version,
        ranAt: ranAt,
        referencedIdCount: json['referencedIdCount'] as int,
        aliasCount: json['aliasCount'] as int,
        targets: {
          for (final MapEntry(:key, :value)
              in (json['targets'] as Map<String, dynamic>).entries)
            key: (
              rewritten: (value as Map<String, dynamic>)['rewritten'] as int,
              dropped: value['dropped'] as int,
            ),
        },
      ),
      _failed => ReferenceIdMigrationFailed(
        referenceDbVersion: version,
        ranAt: ranAt,
      ),
      final outcome => throw FormatException('Unknown outcome', outcome),
    };
  }

  Map<String, Object?> toJson() => {
    'outcome': switch (this) {
      ReferenceIdMigrationSucceeded() => _succeeded,
      ReferenceIdMigrationFailed() => _failed,
    },
    'referenceDbVersion': referenceDbVersion,
    'ranAt': ranAt.millisecondsSinceEpoch,
  };
}

final class ReferenceIdMigrationSucceeded extends ReferenceIdMigrationRun {
  /// Distinct reference IDs found in the user's data.
  final int referencedIdCount;

  /// How many of them the reference database lists as superseded.
  final int aliasCount;

  /// Per table or preference key, only those where anything changed.
  final Map<String, ({int rewritten, int dropped})> targets;

  ReferenceIdMigrationSucceeded({
    required super.referenceDbVersion,
    required super.ranAt,
    required this.referencedIdCount,
    required this.aliasCount,
    required Map<String, ({int rewritten, int dropped})> targets,
  }) : targets = Map.unmodifiable(targets);

  ReferenceIdMigrationSucceeded.fromReport(
    ReferenceIdRewriteReport report, {
    required int referenceDbVersion,
    required DateTime ranAt,
    required int referencedIdCount,
    required int aliasCount,
  }) : this(
         referenceDbVersion: referenceDbVersion,
         ranAt: ranAt,
         referencedIdCount: referencedIdCount,
         aliasCount: aliasCount,
         targets: {
           for (final MapEntry(:key, :value) in report.counts.entries)
             if (value.rewritten > 0 || value.dropped > 0) key: value,
         },
       );

  int get totalRewritten =>
      targets.values.fold(0, (sum, count) => sum + count.rewritten);

  int get totalDropped =>
      targets.values.fold(0, (sum, count) => sum + count.dropped);

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'referencedIdCount': referencedIdCount,
    'aliasCount': aliasCount,
    'targets': {
      for (final MapEntry(:key, :value) in targets.entries)
        key: {'rewritten': value.rewritten, 'dropped': value.dropped},
    },
  };
}

/// The run threw. Its version is not recorded as applied, so the next start
/// runs again.
final class ReferenceIdMigrationFailed extends ReferenceIdMigrationRun {
  const ReferenceIdMigrationFailed({
    required super.referenceDbVersion,
    required super.ranAt,
  });
}
