/// Per-deck configuration for the spaced repetition algorithm.
///
/// Created automatically with defaults when a deck is first accessed.
/// Stored in the `deck_config` table.
enum LearningMode {
  species,
  genus,
  family;

  String get storageValue => name;

  static LearningMode fromStorage(String? value) {
    return LearningMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => LearningMode.species,
    );
  }
}

/// Which name the user is asked to recall: the vernacular ("common") name,
/// or the binomial/scientific name.
enum NameType {
  commonName,
  scientificName;

  String get storageValue => name;

  static NameType fromStorage(String? value) {
    return NameType.values.firstWhere(
      (type) => type.storageValue == value,
      orElse: () => NameType.commonName,
    );
  }
}

/// How the user answers a flashcard during review.
enum ReviewMode {
  /// Tap to flip the card, then self-rate recall with the 4 FSRS buttons.
  flip,

  /// Pick the correct name from 4 options; graded automatically.
  multipleChoice;

  String get storageValue => name;

  static ReviewMode fromStorage(String? value) {
    return ReviewMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => ReviewMode.flip,
    );
  }
}

class DeckConfig {
  final String deckId;

  /// Target recall probability at review time (0.70–0.97).
  /// Higher values → shorter intervals → more reviews.
  final double desiredRetention;

  /// Maximum interval in days (~100 years default).
  final int maximumIntervalDays;

  /// Short-term learning steps for new cards, in minutes.
  /// Cards cycle through these before entering FSRS long-term scheduling.
  final List<Duration> learningSteps;

  /// Short-term re-learning steps after a lapse, in minutes.
  final List<Duration> relearningSteps;

  /// What the user is learning to identify from a card.
  final LearningMode learningMode;

  /// Which name the user is asked to recall: common or scientific.
  final NameType nameType;

  /// How the user answers a card: flip-and-self-rate, or multiple choice.
  final ReviewMode reviewMode;

  const DeckConfig({
    required this.deckId,
    this.desiredRetention = 0.9,
    this.maximumIntervalDays = 36500,
    this.learningSteps = const [Duration(minutes: 1), Duration(minutes: 10)],
    this.relearningSteps = const [Duration(minutes: 10)],
    this.learningMode = LearningMode.species,
    this.nameType = NameType.commonName,
    this.reviewMode = ReviewMode.flip,
  });

  factory DeckConfig.fromMap(Map<String, dynamic> map) {
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

  Map<String, dynamic> toMap() {
    return {
      'deck_id': deckId,
      'desired_retention': desiredRetention,
      'maximum_interval': maximumIntervalDays,
      'learning_steps': _stepsToString(learningSteps),
      'relearning_steps': _stepsToString(relearningSteps),
      'learning_mode': learningMode.storageValue,
      'name_type': nameType.storageValue,
      'review_mode': reviewMode.storageValue,
    };
  }

  /// Encodes a list of Duration as comma-separated minutes: "1,10".
  static String _stepsToString(List<Duration> steps) {
    return steps.map((d) => d.inMinutes).join(',');
  }

  /// Decodes "1,10" → [Duration(minutes:1), Duration(minutes:10)].
  static List<Duration> _stepsFromString(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => Duration(minutes: int.parse(s)))
        .toList();
  }

  DeckConfig copyWith({
    String? deckId,
    double? desiredRetention,
    int? maximumIntervalDays,
    List<Duration>? learningSteps,
    List<Duration>? relearningSteps,
    LearningMode? learningMode,
    NameType? nameType,
    ReviewMode? reviewMode,
  }) {
    return DeckConfig(
      deckId: deckId ?? this.deckId,
      desiredRetention: desiredRetention ?? this.desiredRetention,
      maximumIntervalDays: maximumIntervalDays ?? this.maximumIntervalDays,
      learningSteps: learningSteps ?? this.learningSteps,
      relearningSteps: relearningSteps ?? this.relearningSteps,
      learningMode: learningMode ?? this.learningMode,
      nameType: nameType ?? this.nameType,
      reviewMode: reviewMode ?? this.reviewMode,
    );
  }
}
