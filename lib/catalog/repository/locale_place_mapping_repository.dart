import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';

import 'package:discere/catalog/model/locale_place_mapping.dart';
import 'package:discere/shared/persistence/database_helper.dart';

/// Resolves the user's regional place context from the device locale.
///
/// The two concepts are kept separate intentionally:
///   - **Learning language** (de, en, fr, es) is set by the user on deck
///     level via [LanguageService] and determines which language column is shown.
///   - **Region** (CH, AU, US …) is read implicitly from the device country
///     code and determines which regional name variant is preferred within
///     any language.
///
/// A Swiss user learning English (device: de-CH, learning lang: en) gets:
///   - iNat place_id 7236 (Switzerland) → Swiss-English names first
///   - Fallback to global English names (place_id IS NULL)
///
/// The result is stable for the lifetime of the app process (device locale
/// does not change at runtime), so a single static cache is sufficient.
class LocalePlaceMappingRepository {
  static const _table = 'locale_place_mappings';

  static LocalePlaceMapping? _cache;

  final Database? _injectedDb;

  LocalePlaceMappingRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.referenceDb;

  /// Returns the mapping for the device's current country, or [null] if the
  /// country is unknown or not in the table.
  ///
  /// Lookup is by [country_code_alpha2] only — the learning language is
  /// intentionally ignored here (it is handled by the query layer).
  /// Result is cached after the first DB hit.
  Future<LocalePlaceMapping?> getForCurrentLocale() async {
    if (_cache != null) return _cache;

    final countryCode = _deviceCountryCode();
    if (countryCode == null) return null;

    _cache = await _loadByCountry(countryCode);
    return _cache;
  }

  /// Returns the cached mapping without hitting the DB.
  /// Only non-null after [getForCurrentLocale] has been awaited.
  LocalePlaceMapping? get cached => _cache;

  Future<LocalePlaceMapping?> _loadByCountry(String alpha2) async {
    final db = await _database;
    final rows = await db.query(
      _table,
      where: 'country_code_alpha2 = ?',
      whereArgs: [alpha2],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Returns the ISO-3166 Alpha-2 country code from the device locale,
  /// e.g. 'CH' from 'de-CH'. Returns [null] if unavailable.
  String? _deviceCountryCode() {
    final code = WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    if (code == null || code.isEmpty) return null;
    return code.toUpperCase();
  }

  LocalePlaceMapping _fromRow(Map<String, dynamic> row) {
    return LocalePlaceMapping(
      locale: row['locale'] as String,
      languageCode: row['language_code'] as String,
      countryCodeAlpha2: row['country_code_alpha2'] as String,
      countryCodeNumeric: row['country_code_numeric'] as String,
      inatPlaceId: row['inat_place_id'] as int,
    );
  }
}
