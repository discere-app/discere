import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class DeckConfigRepository {
  final Database? _injectedDb;

  DeckConfigRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

  /// Returns the config for [deckId], or defaults if none exists yet.
  ///
  /// [defaultRetention] is used as the desired-retention default when no row
  /// exists in the database (i.e. the deck has never been configured).
  Future<DeckConfig> getOrDefault(
    String deckId, {
    double defaultRetention = 0.9,
  }) async {
    final db = await _database;
    final result = await db.query(
      'deck_config',
      where: 'deck_id = ?',
      whereArgs: [deckId],
      limit: 1,
    );
    if (result.isEmpty) {
      return DeckConfig(deckId: deckId, desiredRetention: defaultRetention);
    }
    return _fromMap(result.first);
  }

  /// Inserts or replaces the config for a deck.
  Future<void> save(DeckConfig config) async {
    final db = await _database;
    await db.insert(
      'deck_config',
      _toMap(config),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Map<String, dynamic> _toMap(DeckConfig config) {
    return {
      'deck_id': config.deckId,
      'desired_retention': config.desiredRetention,
      'maximum_interval': config.maximumIntervalDays,
      'learning_steps': _stepsToString(config.learningSteps),
      'relearning_steps': _stepsToString(config.relearningSteps),
      'learning_mode': config.learningMode.storageValue,
      'name_type': config.nameType.storageValue,
      'review_mode': config.reviewMode.storageValue,
    };
  }

  DeckConfig _fromMap(Map<String, dynamic> map) {
    return DeckConfig(
      deckId: map['deck_id'] as String,
      desiredRetention: (map['desired_retention'] as num).toDouble(),
      maximumIntervalDays: map['maximum_interval'] as int,
      learningSteps: _stepsFromString(map['learning_steps'] as String?),
      relearningSteps: _stepsFromString(map['relearning_steps'] as String?),
      learningMode: LearningMode.fromStorage(map['learning_mode'] as String?),
      nameType: NameType.fromStorage(map['name_type'] as String?),
      reviewMode: ReviewMode.fromStorage(map['review_mode'] as String?),
    );
  }

  /// Encodes a list of Duration as comma-separated minutes: "1,10".
  String _stepsToString(List<Duration> steps) {
    return steps.map((d) => d.inMinutes).join(',');
  }

  /// Decodes "1,10" → [Duration(minutes:1), Duration(minutes:10)].
  List<Duration> _stepsFromString(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => Duration(minutes: int.parse(s)))
        .toList();
  }
}
