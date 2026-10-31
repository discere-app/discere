import 'package:discere/learning/model/subdeck_structure.dart';

/// What the user changed about a deck's subdecks in Edit Deck: a change
/// rather than the complete division, because the deck can hold what the page
/// never sees — names still waiting to be resolved, species the reference
/// database does not resolve — and all of that has to stay where it is.
class SubdeckEdit {
  /// All subdecks the deck has afterwards, in their order. One missing here
  /// goes.
  final List<SubdeckHeading> subdecks;

  /// The species that change subdeck, each with the one it moves to, or null
  /// for none.
  final Map<String, String?> moves;

  const SubdeckEdit({required this.subdecks, required this.moves});
}
