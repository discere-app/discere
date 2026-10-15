import 'package:discere/shared/persistence/reference_id/reference_id_migration_run.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_rewrite_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final ranAt = DateTime(2026, 10, 15, 9, 30);
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  test('a successful run reads back as it was saved', () async {
    await ReferenceIdMigrationSucceeded(
      referenceDbVersion: 7,
      ranAt: ranAt,
      referencedIdCount: 120,
      aliasCount: 3,
      targets: const {
        'flashcard_stats': (rewritten: 2, dropped: 1),
        'preference watchlist': (rewritten: 1, dropped: 0),
      },
    ).save(preferences);

    final run = ReferenceIdMigrationRun.read(preferences);

    expect(run, isA<ReferenceIdMigrationSucceeded>());
    run as ReferenceIdMigrationSucceeded;
    expect(run.referenceDbVersion, 7);
    expect(run.ranAt, ranAt);
    expect(run.referencedIdCount, 120);
    expect(run.aliasCount, 3);
    expect(run.targets, {
      'flashcard_stats': (rewritten: 2, dropped: 1),
      'preference watchlist': (rewritten: 1, dropped: 0),
    });
    expect(run.totalRewritten, 3);
    expect(run.totalDropped, 1);
  });

  test('a failed run reads back as failed', () async {
    await ReferenceIdMigrationFailed(
      referenceDbVersion: 7,
      ranAt: ranAt,
    ).save(preferences);

    final run = ReferenceIdMigrationRun.read(preferences);

    expect(run, isA<ReferenceIdMigrationFailed>());
    expect(run!.referenceDbVersion, 7);
    expect(run.ranAt, ranAt);
  });

  test('a run from a report keeps only the targets that changed', () {
    final report = ReferenceIdRewriteReport()
      ..record('flashcard_stats', rewritten: 2, dropped: 1)
      ..record('inat_photo_cache', rewritten: 0, dropped: 0);

    final run = ReferenceIdMigrationSucceeded.fromReport(
      report,
      referenceDbVersion: 7,
      ranAt: ranAt,
      referencedIdCount: 10,
      aliasCount: 2,
    );

    expect(run.targets.keys, ['flashcard_stats']);
  });

  group('reads as no run', () {
    test('when nothing was saved', () {
      expect(ReferenceIdMigrationRun.read(preferences), isNull);
    });

    for (final (description, content) in const [
      ('content that is not JSON', 'not json'),
      ('JSON of another shape', '[1, 2]'),
      (
        'an unknown outcome',
        '{"outcome": "x", "referenceDbVersion": 7, '
            '"ranAt": 0}',
      ),
      (
        'a success missing its counts',
        '{"outcome": "succeeded", '
            '"referenceDbVersion": 7, "ranAt": 0}',
      ),
    ]) {
      test('for $description', () async {
        await preferences.setString(ReferenceIdMigrationRun.prefKey, content);
        expect(ReferenceIdMigrationRun.read(preferences), isNull);
      });
    }
  });
}
