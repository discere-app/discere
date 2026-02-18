import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static Future<Database> openAquaFlashDB() async {
    var databasePath = await getDatabasesPath();
    var path = join(databasePath, "aquaflash.db");

    var exists = await databaseExists(path);

    if (exists) {
      if (kDebugMode) {
        print("use existing Database");
      }
      return await openDatabase(path, readOnly: false);
    } else {
      if (kDebugMode) {
        print("Creating new copy from asset");
      }
      try {
        await Directory(dirname(path)).create(recursive: true);
      } catch (_) {}

      ByteData data =
          await rootBundle.load(join("assets", "database", "aquaflash.db"));
      List<int> bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      await File(path).writeAsBytes(bytes, flush: true);

      return await openDatabase(path, readOnly: false);
    }
  }
}
