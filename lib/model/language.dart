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
    throw ArgumentError("Invalid language value: $value");
  }
}
