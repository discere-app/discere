import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/presentation/enrichment_status_presenter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppLocalizations de;

  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    de = await AppLocalizations.delegate.load(const Locale('de'));
  });

  test('shows cooldown text when host cooldown is active', () {
    expect(
      formatDeckPendingStatusLabel(
        de,
        hasActiveHostCooldown: true,
        progressCompleted: 3,
        progressTotal: 10,
      ),
      'Warte auf Umsysteme – wird gleich fortgesetzt',
    );
  });

  test('shows progress fraction when total is known', () {
    expect(
      formatDeckPendingStatusLabel(
        de,
        hasActiveHostCooldown: false,
        progressCompleted: 3,
        progressTotal: 10,
      ),
      'Lade Inhalte (3 / 10 Arten)',
    );
  });

  test('shows indeterminate label when total is zero', () {
    expect(
      formatDeckPendingStatusLabel(
        de,
        hasActiveHostCooldown: false,
        progressCompleted: 0,
        progressTotal: 0,
      ),
      'Lade Inhalte …',
    );
  });

  test('cooldown takes priority over progress fraction', () {
    expect(
      formatDeckPendingStatusLabel(
        de,
        hasActiveHostCooldown: true,
        progressCompleted: 0,
        progressTotal: 0,
      ),
      'Warte auf Umsysteme – wird gleich fortgesetzt',
    );
  });
}
