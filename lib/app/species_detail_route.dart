import 'package:discere/app/species_detail_loader_page.dart';
import 'package:discere/learning/decks/add_to_deck/add_to_deck_sheet.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter/material.dart';

/// A species' detail page as the app opens it from every screen: with "add
/// to deck", and with the species it links to opening the same way.
///
/// Needs no state of any screen, so the composition root can hand it to a
/// slice that may not build it itself — `catalog` knows neither the loader
/// nor the deck sheet.
Widget buildAppSpeciesDetailPage(String speciesId, [Language? language]) {
  return SpeciesDetailLoaderPage(
    speciesId: speciesId,
    language: language,
    buildSpeciesDetailPage: buildAppSpeciesDetailPage,
    onAddToDeck: addAppSpeciesToDeck,
  );
}

/// The app's "add to deck" for a species page or the search: the deck sheet.
Future<bool> addAppSpeciesToDeck(
  BuildContext context,
  Set<String> speciesIds,
  Set<String> speciesNames,
) {
  return showAddToDeckSheet(
    context,
    speciesIds: speciesIds,
    speciesNames: speciesNames,
  );
}
