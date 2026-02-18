import 'package:sqflite/sqflite.dart';

Future<void> migrate(Database db) async {
  await db.execute('''
    CREATE VIRTUAL TABLE IF NOT EXISTS search_table
    USING fts5(
      id,
      name,
      common_name,
      category,  -- Kann "species", "genus", "family", "order", oder "class" sein
      super_category,  -- Übergeordnete Kategorie (z.B. für Genera ist das die Familie, für Species ist das das Genus)
      content=''
    )
  ''');
}
