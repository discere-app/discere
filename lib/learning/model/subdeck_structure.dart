import 'package:discere/learning/model/create_subdeck.dart';

/// One subdeck of a [SubdeckStructure]: its id and name, without species.
typedef SubdeckHeading = ({String id, String name});

/// A deck's subdecks with their species looked up: what a deck's JSON says
/// about its subdecks once its names have been resolved against the local
/// catalog. What gets stored for a deck.
class SubdeckStructure {
  /// In the order the JSON lists them.
  final List<SubdeckHeading> subdecks;

  /// The subdeck each species belongs to. A species of the deck missing here
  /// belongs to none.
  final Map<String, String> subdeckIdBySpeciesId;

  /// The subdeck of each name that did not resolve, for when the enrichment
  /// queue resolves it and adds its species.
  final Map<String, String> subdeckIdByUnresolvedName;

  const SubdeckStructure({
    required this.subdecks,
    required this.subdeckIdBySpeciesId,
    required this.subdeckIdByUnresolvedName,
  });

  /// A deck without subdecks.
  static const none = SubdeckStructure(
    subdecks: [],
    subdeckIdBySpeciesId: {},
    subdeckIdByUnresolvedName: {},
  );

  /// [subdecks] with each name looked up in [speciesIdByName]. Two names of
  /// one species in different subdecks put it in the first, and so does one
  /// name not resolved yet that two subdecks list.
  factory SubdeckStructure.resolve(
    List<CreateSubdeck>? subdecks,
    Map<String, String> speciesIdByName,
  ) {
    if (subdecks == null || subdecks.isEmpty) return none;
    final bySpeciesId = <String, String>{};
    final byUnresolvedName = <String, String>{};
    for (final subdeck in subdecks) {
      for (final name in subdeck.speciesNames) {
        final speciesId = speciesIdByName[name];
        if (speciesId == null) {
          byUnresolvedName.putIfAbsent(name, () => subdeck.id);
        } else {
          bySpeciesId.putIfAbsent(speciesId, () => subdeck.id);
        }
      }
    }
    return SubdeckStructure(
      subdecks: [
        for (final subdeck in subdecks) (id: subdeck.id, name: subdeck.name),
      ],
      subdeckIdBySpeciesId: bySpeciesId,
      subdeckIdByUnresolvedName: byUnresolvedName,
    );
  }

  /// This structure for a deck holding [speciesIds]: a species outside the
  /// deck has no place in it.
  SubdeckStructure restrictedTo(Set<String> speciesIds) => SubdeckStructure(
    subdecks: subdecks,
    subdeckIdBySpeciesId: {
      for (final MapEntry(key: speciesId, value: subdeckId)
          in subdeckIdBySpeciesId.entries)
        if (speciesIds.contains(speciesId)) speciesId: subdeckId,
    },
    subdeckIdByUnresolvedName: subdeckIdByUnresolvedName,
  );
}
