/// The order decks are enriched in was a sort closure inside a private
/// scheduling method, reachable only by driving the whole queue service
/// against a database. It is the one place in that service with real
/// domain reasoning, and it had no test.
library;

import 'package:discere/enrichment/queue/service/deck_enrichment_priority.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the deck sharing the most species with the batch goes first', () {
    // b shares both of its species with others; a and c share one each.
    final order = prioritizeDecksBySharedSpecies(
      ['a', 'b', 'c'],
      {
        'a': {'s1', 'unique-a'},
        'b': {'s1', 's2'},
        'c': {'s2', 'unique-c'},
      },
    );

    expect(order.first, 'b');
  });

  test('a deck of entirely unique species sorts last', () {
    final order = prioritizeDecksBySharedSpecies(
      ['loner', 'x', 'y'],
      {
        'loner': {'only-here'},
        'x': {'shared'},
        'y': {'shared'},
      },
    );

    expect(order.last, 'loner');
  });

  test('equal scores keep the order the caller passed in', () {
    final order = prioritizeDecksBySharedSpecies(
      ['second', 'first'],
      {
        'second': {'s1'},
        'first': {'s2'},
      },
    );

    expect(order, ['second', 'first']);
  });

  test('a bigger deck outranks a smaller one at the same overlap', () {
    // Both share s1, but 'big' also carries two more species of its own,
    // each contributing one — enriching it clears more of the batch.
    final order = prioritizeDecksBySharedSpecies(
      ['small', 'big'],
      {
        'small': {'s1'},
        'big': {'s1', 'x', 'y'},
      },
    );

    expect(order, ['big', 'small']);
  });

  test('a deck the map knows nothing about scores zero rather than throwing', () {
    final order = prioritizeDecksBySharedSpecies(
      ['known', 'unknown'],
      {
        'known': {'s1'},
      },
    );

    expect(order, ['known', 'unknown']);
  });

  test('an empty batch stays empty', () {
    expect(prioritizeDecksBySharedSpecies(const [], const {}), isEmpty);
  });
}
