import 'package:discere/learning/import/import_online_deck_presenter.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const presenter = ImportOnlineDeckPresenter();

  CreateDeck remoteDeck({String? sourceId, DateTime? updatedAt}) => CreateDeck(
    name: 'Remote Deck',
    description: 'desc',
    sourceId: sourceId,
    updatedAt: updatedAt,
  );

  BaseDeck localDeck({String? sourceId, DateTime? updatedAt}) =>
      BaseDeck('local-1', 'Local Deck', 'desc', sourceId: sourceId, updatedAt: updatedAt);

  group('ImportOnlineDeckPresenter', () {
    test('returns notImported when the entry has no sourceId', () {
      final status = presenter.statusFor(remoteDeck(), {});
      expect(status, ImportOnlineDeckStatus.notImported);
    });

    test('returns notImported when no local deck matches the sourceId', () {
      final status = presenter.statusFor(
        remoteDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 1, 1)),
        {},
      );
      expect(status, ImportOnlineDeckStatus.notImported);
    });

    test('returns updateAvailable when the remote entry is newer', () {
      final status = presenter.statusFor(
        remoteDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 2, 1)),
        {'src-1': localDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 1, 1))},
      );
      expect(status, ImportOnlineDeckStatus.updateAvailable);
    });

    test('returns upToDate when the local copy is current', () {
      final status = presenter.statusFor(
        remoteDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 1, 1)),
        {'src-1': localDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 2, 1))},
      );
      expect(status, ImportOnlineDeckStatus.upToDate);
    });

    test(
      'returns updateAvailable when the local deck has no tracked updatedAt',
      () {
        final status = presenter.statusFor(
          remoteDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 1, 1)),
          {'src-1': localDeck(sourceId: 'src-1')},
        );
        expect(status, ImportOnlineDeckStatus.updateAvailable);
      },
    );

    test('returns upToDate when the remote entry has no updatedAt', () {
      final status = presenter.statusFor(
        remoteDeck(sourceId: 'src-1'),
        {'src-1': localDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 1, 1))},
      );
      expect(status, ImportOnlineDeckStatus.upToDate);
    });
  });
}
