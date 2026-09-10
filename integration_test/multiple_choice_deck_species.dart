/// The species the multiple-choice review test builds its deck from.
///
/// Shared with `test/learning/flashcard/service/`'s guard test rather than
/// spelled out twice: that test asserts, against the checked-in reference
/// fixture, that every one of these yields a full set of answer options. The
/// requirement is not "four distinct common names" but "three taxonomically
/// close relatives per card" — a card whose pool comes up short falls back to
/// flip mode for that card alone (see `DeckPageState._updateCurrentOptions`),
/// which reaches the test only as a timeout waiting for options that will
/// never render. Keeping one list means the guard cannot drift off the deck
/// it is guarding.
///
/// These four are all Teleostei, so each card draws its three distractors
/// from the other three deck species without depending on what the fixture
/// happens to hold around them.
const multipleChoiceDeckSpecies = <String>[
  'Amphiprion ocellaris',
  'Abramis brama',
  'Oncorhynchus mykiss',
  'Thymallus thymallus',
];
