import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/flashcard/deck_session_presenter.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:flutter_test/flutter_test.dart';

DeckEnrichmentInfo _info({
  EnrichmentJobStatus status = EnrichmentJobStatus.completed,
  DateTime? lastCompletedAt,
}) {
  return DeckEnrichmentInfo(
    status: status,
    lastCompletedAt: lastCompletedAt,
    lastAttemptedAt: null,
  );
}

Species _species(String id) {
  return Species(
    id,
    id,
    'fishbase',
    id,
    const {},
    Classification(
      'Genus',
      const {},
      null,
      'Family',
      const {},
      'Order',
      const {},
      'Class',
      const {},
      null,
    ),
    const [],
  );
}

SpeciesWithLocalImages _cardWithImage(String id) {
  return SpeciesWithLocalImages(_species(id), [
    LocalPicture(
      Picture(id: 'pic-$id', species: id, origin: 'inaturalist', isUsable: 1),
      '/tmp/$id.jpg',
    ),
  ]);
}

SpeciesWithLocalImages _cardWithoutImage(String id) {
  return SpeciesWithLocalImages(_species(id), const []);
}

void main() {
  const presenter = DeckSessionPresenter();

  group('DeckSessionPresenter.effectiveReviewMode', () {
    test('stays multipleChoice when options were built for this card', () {
      final result = presenter.effectiveReviewMode(
        reviewMode: ReviewMode.multipleChoice,
        hasOptions: true,
      );
      expect(result, ReviewMode.multipleChoice);
    });

    test(
      'falls back to flip for this card when multipleChoice has no options',
      () {
        final result = presenter.effectiveReviewMode(
          reviewMode: ReviewMode.multipleChoice,
          hasOptions: false,
        );
        expect(result, ReviewMode.flip);
      },
    );

    test('flip mode is unaffected by hasOptions', () {
      expect(
        presenter.effectiveReviewMode(
          reviewMode: ReviewMode.flip,
          hasOptions: false,
        ),
        ReviewMode.flip,
      );
      expect(
        presenter.effectiveReviewMode(
          reviewMode: ReviewMode.flip,
          hasOptions: true,
        ),
        ReviewMode.flip,
      );
    });
  });

  group('DeckSessionPresenter.shouldRequeue', () {
    test('requeues learning and relearning cards', () {
      expect(presenter.shouldRequeue(CardState.learning), isTrue);
      expect(presenter.shouldRequeue(CardState.relearning), isTrue);
    });

    test('does not requeue new or review cards', () {
      expect(presenter.shouldRequeue(CardState.newCard), isFalse);
      expect(presenter.shouldRequeue(CardState.review), isFalse);
    });
  });

  group('DeckSessionPresenter.shouldRefreshAfterEnrichmentChange', () {
    test('does not refresh while the job is still active', () {
      final result = presenter.shouldRefreshAfterEnrichmentChange(
        previous: _info(status: EnrichmentJobStatus.queued),
        next: _info(status: EnrichmentJobStatus.runningForeground),
      );
      expect(result, isFalse);
    });

    test('refreshes when a new completion timestamp just landed', () {
      final t1 = DateTime(2026, 1, 1);
      final t2 = DateTime(2026, 1, 2);
      final result = presenter.shouldRefreshAfterEnrichmentChange(
        previous: _info(
          status: EnrichmentJobStatus.runningForeground,
          lastCompletedAt: t1,
        ),
        next: _info(status: EnrichmentJobStatus.completed, lastCompletedAt: t2),
      );
      expect(result, isTrue);
    });

    test('refreshes when a previously-active job stops even without a new '
        'completion (cancelled/paused/failed)', () {
      final result = presenter.shouldRefreshAfterEnrichmentChange(
        previous: _info(status: EnrichmentJobStatus.runningForeground),
        next: _info(status: EnrichmentJobStatus.cancelled),
      );
      expect(result, isTrue);
    });

    test(
      'does not refresh when nothing changed (both idle, same completion)',
      () {
        final t1 = DateTime(2026, 1, 1);
        final result = presenter.shouldRefreshAfterEnrichmentChange(
          previous: _info(
            status: EnrichmentJobStatus.completed,
            lastCompletedAt: t1,
          ),
          next: _info(
            status: EnrichmentJobStatus.completed,
            lastCompletedAt: t1,
          ),
        );
        expect(result, isFalse);
      },
    );

    test('does not refresh on repeated notifications for the same already-seen '
        'completion', () {
      final t1 = DateTime(2026, 1, 1);
      // previous already reflects the same completion (e.g. a second,
      // redundant listener notification with no real change).
      final result = presenter.shouldRefreshAfterEnrichmentChange(
        previous: _info(
          status: EnrichmentJobStatus.completed,
          lastCompletedAt: t1,
        ),
        next: _info(status: EnrichmentJobStatus.completed, lastCompletedAt: t1),
      );
      expect(result, isFalse);
    });
  });

  group('DeckSessionPresenter.filterReviewableCards', () {
    test('returns all cards unchanged once image stages are complete', () {
      final cards = [_cardWithImage('sp1'), _cardWithoutImage('sp2')];
      final result = presenter.filterReviewableCards(
        cards,
        imageStagesComplete: true,
      );
      expect(result, cards);
    });

    test('hides cards without a local image while image stages are still '
        'loading', () {
      final withImage = _cardWithImage('sp1');
      final result = presenter.filterReviewableCards([
        withImage,
        _cardWithoutImage('sp2'),
      ], imageStagesComplete: false);
      expect(result, [withImage]);
    });

    test('returns an empty list when no card has an image yet and stages are '
        'still loading', () {
      final result = presenter.filterReviewableCards([
        _cardWithoutImage('sp1'),
        _cardWithoutImage('sp2'),
      ], imageStagesComplete: false);
      expect(result, isEmpty);
    });
  });
}
