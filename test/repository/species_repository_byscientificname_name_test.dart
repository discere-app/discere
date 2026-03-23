import 'dart:io';
import 'dart:math';

import 'package:discere/persistence/species_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Map<String, dynamic>> initializeTestDatabase() async {
  // Erzeuge einen eindeutigen Dateinamen für die Testdatenbank im Systemtemp-Verzeichnis
  final tempDir = Directory.systemTemp;
  final uniqueSuffix =
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  final dbPath = join(tempDir.path, "test_aquaflash_$uniqueSuffix.db");

  // Lade die originale Datenbank aus den Assets
  ByteData data = await rootBundle.load("assets/database/discere_reference.db");
  List<int> bytes =
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

  // Schreibe die Daten in die temporäre Datei
  await File(dbPath).writeAsBytes(bytes, flush: true);

  // Öffne die Test-Datenbank
  final database = await openDatabase(dbPath, readOnly: false);

  return {'database': database, 'dbPath': dbPath};
}

void main() {
  // Wichtig: FFI-Backend initialisieren, damit openDatabase in der Testumgebung funktioniert.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Stelle sicher, dass Flutter Bindings initialisiert sind.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late String dbPath;
  late SpeciesRepository repository;

  setUp(() async {
    // Initialisiere die temporäre Test-Datenbank
    final dbData = await initializeTestDatabase();
    database = dbData['database'] as Database;
    dbPath = dbData['dbPath'] as String;

    // Initialisiere dein Repository mit der Test-Datenbank
    repository = SpeciesRepository(database: database);

    // Hier kannst du weitere Testdaten einfügen, falls benötigt.
  });

  tearDown(() async {
    // Schließe die Datenbank
    await database.close();
    // Lösche die temporäre Datenbankdatei, falls vorhanden
    final file = File(dbPath);
    if (await file.exists()) {
      await file.delete();
    }
  });

  test('getSpeciesIdsByScientificNames liefert die korrekten IDs', () async {
    // Arrange: Erstelle eine Liste von Tupeln (Genus, Species)
    final scientificNames = [
      ('Carcharodon', 'carcharias'),
      ('Galeocerdo', 'cuvier'),
      ('Prionace', 'glauca'),
      ('Rhincodon', 'typus'),
      ('Sphyrna', 'mokarran'),
      ('Alopias', 'vulpinus')
    ];

    final result =
        await repository.getSpeciesIdsByScientificNames(scientificNames);

    expect(result.length, 6);
    expect(result,
        containsAll({'fishbase:2081', 'fishbase:2535', 'fishbase:751', 'fishbase:886', 'fishbase:898', 'fishbase:914'}));
  });

  test('should return empty list for non-existing scientific name', () async {
    // Arrange
    final invalidScientificName = [('Invalidus', 'ficticius')];

    // Act
    final result =
        await repository.getSpeciesIdsByScientificNames(invalidScientificName);

    // Assert
    expect(result, isEmpty);
  });

  test('should return empty list for empty scientific name', () async {
    // Act
    final result = await repository.getSpeciesIdsByScientificNames(<(String, String)>[]);

    // Assert
    expect(result, isEmpty);
  });
}
