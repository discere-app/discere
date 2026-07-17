import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

@JsonEnum(valueField: 'value')
enum Language {
  de(0),
  en(1),
  fr(2),
  es(3);

  const Language(this.value);
  final int value;

  static Language fromValue(int value) {
    for (Language language in Language.values) {
      if (language.value == value) {
        return language;
      }
    }
    throw ArgumentError('Invalid language value: $value');
  }

  Locale toLocale() {
    return Locale(name);
  }

  static Language getSystemLanguage() {
    final String deviceLanguage =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    for (Language language in Language.values) {
      if (language.name == deviceLanguage) {
        return language;
      }
    }
    return Language.en; // Fallback to English
  }
}
