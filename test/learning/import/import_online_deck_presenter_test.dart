import 'package:discere/learning/import/import_online_deck_presenter.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_supersession.dart';
import 'package:flutter_test/flutter_test.dart';

DeckSupersession _locals(List<BaseDeck> decks) =>
    DeckSupersession(catalog: const [], localDecks: decks);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const presenter = ImportOnlineDeckPresenter();

  CreateDeck remoteDeck({
    String? sourceId,
    DateTime? updatedAt,
    List<String>? supersedes,
  }) => CreateDeck(
    name: 'Remote Deck',
    description: 'desc',
    sourceId: sourceId,
    updatedAt: updatedAt,
    supersedes: supersedes,
  );

  BaseDeck localDeck({String? sourceId, DateTime? updatedAt}) =>
      BaseDeck(
  id: 'local-1',
  name: 'Local Deck',
  description: 'desc', sourceId: sourceId, updatedAt: updatedAt);

  group('ImportOnlineDeckPresenter', () {
    test('returns notImported when the entry has no sourceId', () {
      final status = presenter.statusFor(remoteDeck(), _locals([]));
      expect(status, ImportOnlineDeckStatus.notImported);
    });

    test('returns notImported when no local deck matches the sourceId', () {
      final status = presenter.statusFor(
        remoteDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 1, 1)),
        _locals([]),
      );
      expect(status, ImportOnlineDeckStatus.notImported);
    });

    test('returns updateAvailable when the remote entry is newer', () {
      final status = presenter.statusFor(
        remoteDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 2, 1)),
        _locals([localDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 1, 1))]),
      );
      expect(status, ImportOnlineDeckStatus.updateAvailable);
    });

    test('returns upToDate when the local copy is current', () {
      final status = presenter.statusFor(
        remoteDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 1, 1)),
        _locals([localDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 2, 1))]),
      );
      expect(status, ImportOnlineDeckStatus.upToDate);
    });

    test(
      'returns updateAvailable when the local deck has no tracked updatedAt',
      () {
        final status = presenter.statusFor(
          remoteDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 1, 1)),
          _locals([localDeck(sourceId: 'src-1')]),
        );
        expect(status, ImportOnlineDeckStatus.updateAvailable);
      },
    );

    test('returns upToDate when the remote entry has no updatedAt', () {
      final status = presenter.statusFor(
        remoteDeck(sourceId: 'src-1'),
        _locals([localDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 1, 1))]),
      );
      expect(status, ImportOnlineDeckStatus.upToDate);
    });

    test('returns supersedesLocal when the entry supersedes a local deck it '
        'does not stand for itself', () {
      final status = presenter.statusFor(
        remoteDeck(sourceId: 'src-new', supersedes: ['src-1']),
        _locals([localDeck(sourceId: 'src-1')]),
      );
      expect(status, ImportOnlineDeckStatus.supersedesLocal);
    });

    test('an entry already imported shows its own status, whatever it '
        'supersedes', () {
      final status = presenter.statusFor(
        remoteDeck(sourceId: 'src-1', supersedes: ['src-old']),
        DeckSupersession(
          catalog: const [],
          localDecks: [
            localDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 2, 1)),
            localDeck(sourceId: 'src-old'),
          ],
        ),
      );
      expect(status, ImportOnlineDeckStatus.upToDate);
    });
  });
}
