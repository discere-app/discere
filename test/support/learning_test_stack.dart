import 'dart:io';

import 'package:discere/app/wiring/deck_lifecycle_wiring.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/repository/taxon_assignment_repository.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_mode_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/repository/subdeck_repository.dart';
import 'package:discere/learning/service/answerable_cards_service.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/persistence/user_data_writes.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../mocks.mocks.dart';
import 'in_memory_user_database.dart';

/// Species of the reference fixture by their scientific name, for decks
/// built from names the way an import builds them.
const fixtureSpeciesIds = {
  'Carcharodon carcharias': 'discere:species:694',
  'Prionace glauca': 'discere:species:834',
  'Sphyrna lewini': 'discere:species:847',
  'Galeocerdo cuvier': 'discere:species:822',
  'Rhincodon typus': 'discere:species:1872',
  'Amphiprion ocellaris': 'discere:species:6002',
};

/// The deck services over real databases: a copy of the reference fixture
/// and an in-memory user database, wired the way the app wires them, so a
/// test sees what the user would — names resolved, cascades fired.
///
/// Requires `TestWidgetsFlutterBinding.ensureInitialized()`. Starts from
/// empty preferences, as it starts from an empty user database.
class LearningTestStack {
  LearningTestStack._(
    this._tempDir,
    this.referenceDb,
    this.userDb,
    this.preferences,
  ) : stats = FlashcardStatRepository(database: userDb),
      deckRepository = DeckRepository(database: userDb),
      deckConfigs = DeckConfigRepository(database: userDb),
      subdecks = SubdeckRepository(database: userDb),
      speciesRepository = SpeciesRepository(
        database: referenceDb,
        userDatabase: userDb,
      );

  final Directory _tempDir;
  final Database referenceDb;
  final Database userDb;
  final FlashcardStatRepository stats;
  final DeckRepository deckRepository;
  final DeckConfigRepository deckConfigs;
  final SubdeckRepository subdecks;
  final SpeciesRepository speciesRepository;
  final UserPreferencesService preferences;
  final UserDataWrites writes = UserDataWrites();

  late final AnswerableCardsService answerableCards = AnswerableCardsService(
    stats,
    FlashcardStatModeRepository(database: userDb),
    TaxonAssignmentRepository(database: referenceDb),
    subdecks,
  );

  late final DecksService decksService = DecksService(
    deckRepository,
    stats,
    speciesRepository,
    MockImageService(),
    subdeckRepository: subdecks,
    deckConfigRepository: deckConfigs,
    lifecycleObserver: DeckLifecycleWiring(
      deckConfigRepository: deckConfigs,
      userPreferences: preferences,
      userDataWrites: writes,
    ),
    answerableCards: answerableCards,
    userDataWrites: writes,
  );

  late final DeckImportService importService = DeckImportService(
    decksService,
    speciesRepository,
    userDataWrites: writes,
  );

  static Future<LearningTestStack> open() async {
    sqfliteFfiInit();
    final tempDir = await Directory.systemTemp.createTemp('learning_stack');
    final path = p.join(tempDir.path, 'reference.db');
    await File('test/fixtures/discere_reference_test.db').copy(path);
    final referenceDb = await databaseFactoryFfi.openDatabase(path);
    final userDb = await openInMemoryUserDatabase();
    SharedPreferences.setMockInitialValues({});
    final preferences = UserPreferencesService(
      await SharedPreferences.getInstance(),
    );
    return LearningTestStack._(tempDir, referenceDb, userDb, preferences);
  }

  /// Completes once the writes a deck creation leaves running — its
  /// `deck_config` row — are done.
  Future<void> settled() => writes.drained();

  Future<void> close() async {
    // Closed under a write still running, the database would fail it.
    await settled();
    await userDb.close();
    await referenceDb.close();
    await _tempDir.delete(recursive: true);
  }
}
