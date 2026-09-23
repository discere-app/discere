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
