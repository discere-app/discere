import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/enrichment_progress_status.dart';
import 'package:discere/shared/presentation/enrichment_status_presenter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppLocalizations de;

  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    de = await AppLocalizations.delegate.load(const Locale('de'));
  });

  test('shows source cooldown detail when a host cooldown is active', () {
    const status = INatEnrichmentStatus(
      isRunning: true,
      hasPendingWork: true,
      hasActiveWork: true,
      hasActiveHostCooldown: true,
      phase: INatEnrichmentPhase.inat,
      completed: 3,
      total: 10,
      readyDeckCount: 1,
      totalDeckCount: 2,
    );

    expect(
      formatEnrichmentDetail(de, status),
      'Eine Datenquelle ist vorübergehend langsam. Die Anreicherung läuft später automatisch weiter.',
    );
  });

  test('keeps foreground title and phase detail while work is pending', () {
    const status = INatEnrichmentStatus(
      isRunning: false,
      hasPendingWork: true,
      hasActiveWork: true,
      hasActiveHostCooldown: false,
      preferBackgroundMessaging: false,
      phase: INatEnrichmentPhase.inat,
      completed: 19,
      total: 27,
      readyDeckCount: 4,
      totalDeckCount: 4,
    );

    expect(formatEnrichmentTitle(de, status), 'Deck-Anreicherung läuft');
    expect(formatEnrichmentDetail(de, status), 'Fotos werden ergänzt (19/27)');
  });

  test(
    'shows retry detail when pending work is waiting for the next attempt',
    () {
      final status = INatEnrichmentStatus(
        isRunning: false,
        hasPendingWork: true,
        hasActiveWork: false,
        hasActiveHostCooldown: false,
        nextAttemptAt: DateTime(2026, 4, 25, 14, 30),
        phase: INatEnrichmentPhase.inat,
        completed: 0,
        total: 27,
        readyDeckCount: 0,
        totalDeckCount: 1,
      );

      expect(
        formatEnrichmentDetail(
          de,
          status,
          localeTag: 'de',
          now: DateTime(2026, 4, 25, 9),
        ),
        'iNaturalist ist gerade langsam. Nächster Versuch ca. um 14:30',
      );
    },
  );

  test(
    'shows background wording only when background messaging is preferred',
    () {
      const status = INatEnrichmentStatus(
        isRunning: false,
        hasPendingWork: true,
        hasActiveWork: true,
        hasActiveHostCooldown: false,
        preferBackgroundMessaging: true,
        phase: INatEnrichmentPhase.inat,
        completed: 19,
        total: 27,
        readyDeckCount: 4,
        totalDeckCount: 4,
      );

      expect(
        formatEnrichmentTitle(de, status),
        'Deck-Anreicherung läuft im Hintergrund weiter',
      );
      expect(formatEnrichmentDetail(de, status), 'Läuft im Hintergrund weiter');
    },
  );

  test('shows ready-continuing deck label after quick pass', () {
    expect(
      formatDeckPendingStatusLabel(
        de,
        hasActiveHostCooldown: false,
        isQuickPassReady: true,
        phase: INatEnrichmentPhase.inat,
        fallback: 'fallback',
      ),
      'Bereit, weitere Anreicherung läuft',
    );
  });

  test('shows waiting-for-source deck label during host cooldown', () {
    expect(
      formatDeckPendingStatusLabel(
        de,
        hasActiveHostCooldown: true,
        isQuickPassReady: true,
        phase: INatEnrichmentPhase.inat,
        fallback: 'fallback',
      ),
      'Wartet auf Datenquelle',
    );
  });

  test('shows retry time deck label while a retry is scheduled', () {
    expect(
      formatDeckPendingStatusLabel(
        de,
        hasActiveHostCooldown: false,
        isQuickPassReady: false,
        nextAttemptAt: DateTime(2026, 4, 25, 14, 30),
        localeTag: 'de',
        now: DateTime(2026, 4, 25, 9),
        phase: INatEnrichmentPhase.inat,
        fallback: 'fallback',
      ),
      'iNaturalist gerade langsam, nächster Versuch ca. um 14:30',
    );
  });
}
