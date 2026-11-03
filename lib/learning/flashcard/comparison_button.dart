import 'package:discere/catalog/comparison/add_to_comparison_sheet.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/flashcard/glass_button_frame.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Adds the card's species to a comparison — on the back of the card, where
/// the answer is known; never another species, not even one picked wrongly
/// in multiple choice.
class ComparisonButton extends StatelessWidget {
  final Species species;

  const ComparisonButton({required this.species, super.key});

  @override
  Widget build(BuildContext context) {
    return GlassButtonFrame(
      child: IconButton(
        key: const Key('flashcard_compare_button'),
        tooltip: context.loc.comparisonAdd,
        icon: Icon(Icons.compare, color: Colors.white.withValues(alpha: 0.85)),
        onPressed: () => showAddToComparisonSheet(
          context,
          speciesIds: {species.id},
          speciesNames: {species.getBinomialName()},
        ),
      ),
    );
  }
}
