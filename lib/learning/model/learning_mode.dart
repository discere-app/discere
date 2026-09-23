/// Which taxonomic rank a deck asks the user to recall.
///
/// A species deck shows the animal and asks for the species; a genus deck
/// asks only for the genus, which is what a beginner can realistically name
/// from a photo.
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
