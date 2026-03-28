import 'package:discere/persistence/deck_repository.dart';
import 'package:discere/persistence/flash_card_stat_repository.dart';
import 'package:discere/service/common/image_service.dart';
import 'package:discere/persistence/species_repository.dart';
import 'package:discere/service/common/import_export_service.dart';
import 'package:discere/service/common/notification_service.dart';
import 'package:discere/service/learning/decks_service.dart';
import 'package:mockito/annotations.dart';
import 'package:shared_preferences/shared_preferences.dart';

@GenerateNiceMocks([
  MockSpec<SharedPreferences>(),
  MockSpec<DeckRepository>(),
  MockSpec<SpeciesRepository>(),
  MockSpec<FlashCardStatRepository>(),
  MockSpec<ImageService>(),
  MockSpec<NotificationService>(),
  MockSpec<DecksService>(),
  MockSpec<ImportExportService>(),
])
void main() {}
