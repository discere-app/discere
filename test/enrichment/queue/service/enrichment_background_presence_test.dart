import 'package:discere/enrichment/queue/model/inat_enrichment_status.dart';
import 'package:discere/enrichment/queue/service/enrichment_background_presence.dart';
import 'package:discere/shared/service/foreground_service_keeper.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingKeeper implements ForegroundServiceKeeper {
  final List<String> calls = <String>[];
  String? lastTitle;
  String? lastText;
  bool running = false;

  @override
  Future<void> initialize() async => calls.add('initialize');

  @override
  Future<bool> get isRunning async => running;

  @override
  Future<void> startKeepingAlive() async {
    running = true;
    calls.add('start');
  }

  @override
  Future<void> stopKeepingAlive() async {
    running = false;
    calls.add('stop');
  }

  @override
  Future<void> updateNotificationContent({
    required String title,
    required String text,
  }) async {
    lastTitle = title;
    lastText = text;
    calls.add('content');
  }
}

class _Network implements NetworkAvailability {
  @override
  bool isOnline = true;

  @override
  Stream<bool> get onlineStatusChanges => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isOnWifi() async => isOnline;
}

INatEnrichmentStatus status({
  bool hasActiveWork = false,
  bool hasActiveHostCooldown = false,
  bool preferBackgroundMessaging = false,
  int completed = 0,
  int total = 0,
}) => INatEnrichmentStatus(
  isRunning: hasActiveWork,
  hasPendingWork: hasActiveWork || hasActiveHostCooldown,
  hasActiveWork: hasActiveWork,
  hasActiveHostCooldown: hasActiveHostCooldown,
  preferBackgroundMessaging: preferBackgroundMessaging,
  phase: INatEnrichmentPhase.idle,
  completed: completed,
  total: total,
);

void main() {
  late _RecordingKeeper keeper;
  late _Network network;

  EnrichmentBackgroundPresence build({bool enabled = true}) =>
      EnrichmentBackgroundPresence(
        keeper: keeper,
        networkAvailability: network,
        enabled: enabled,
      );

  setUp(() {
    keeper = _RecordingKeeper();
    network = _Network();
  });

  group('whether the presence goes up', () {
    test('backgrounded with active work: yes', () async {
      await build().sync(
        isInForeground: false,
        status: status(hasActiveWork: true),
      );

      expect(keeper.calls, contains('start'));
    });

    test('in the foreground: no — the in-app banner already says it', () async {
      await build().sync(
        isInForeground: true,
        status: status(hasActiveWork: true),
      );

      expect(keeper.calls, isEmpty);
    });

    test('backgrounded with nothing to do: no', () async {
      await build().sync(isInForeground: false, status: status());

      expect(keeper.calls, isEmpty);
    });

    test('offline: no — nothing would progress anyway', () async {
      network.isOnline = false;

      await build().sync(
        isInForeground: false,
        status: status(hasActiveWork: true),
      );

      expect(keeper.calls, isEmpty);
    });

    test('an active cooldown alone keeps it up', () async {
      // Otherwise a short rate limit would tear the notification down only to
      // bring it straight back — and the process might not survive to resume.
      await build().sync(
        isInForeground: false,
        status: status(hasActiveHostCooldown: true),
      );

      expect(keeper.calls, contains('start'));
    });

    test('disabled instances never put one up', () async {
      await build(enabled: false).sync(
        isInForeground: false,
        status: status(hasActiveWork: true),
      );

      expect(keeper.calls, isEmpty);
    });
  });

  group('not thrashing the service', () {
    test('repeated syncs with the same answer start it once', () async {
      final presence = build();
      for (var i = 0; i < 3; i++) {
        await presence.sync(
          isInForeground: false,
          status: status(hasActiveWork: true),
        );
      }

      expect(keeper.calls.where((c) => c == 'start'), hasLength(1));
    });

    test('it comes down when the work ends, and only once', () async {
      final presence = build();
      await presence.sync(
        isInForeground: false,
        status: status(hasActiveWork: true),
      );
      keeper.calls.clear();

      await presence.sync(isInForeground: false, status: status());
      await presence.sync(isInForeground: false, status: status());

      expect(keeper.calls, ['stop']);
    });

    test('stop on a presence that was never up does nothing', () async {
      await build().stop();

      expect(keeper.calls, isEmpty);
    });
  });

  group('notification content', () {
    test('is refreshed while the presence is up', () async {
      await build().sync(
        isInForeground: false,
        status: status(hasActiveWork: true, completed: 3, total: 10),
      );

      expect(keeper.lastTitle, isNotNull);
      expect(keeper.lastText, isNotNull);
    });

    test('is not written while in the foreground', () async {
      await build().sync(
        isInForeground: true,
        status: status(hasActiveWork: true),
      );

      expect(keeper.lastTitle, isNull);
    });

    test('the title follows preferBackgroundMessaging', () async {
      final presence = build();
      await presence.sync(
        isInForeground: false,
        status: status(hasActiveWork: true),
      );
      final foregroundTitle = keeper.lastTitle;

      await presence.sync(
        isInForeground: false,
        status: status(hasActiveWork: true, preferBackgroundMessaging: true),
      );

      expect(keeper.lastTitle, isNot(foregroundTitle));
    });
  });

  test('ensureStarted skips the state checks a scheduled deck already made',
      () async {
    // Called for a deck scheduled while backgrounded: the work starts now, so
    // the process has to survive it without waiting for the next refresh.
    await build().ensureStarted();

    expect(keeper.calls, ['start']);
  });

  test('ensureStarted stays inert when disabled', () async {
    await build(enabled: false).ensureStarted();

    expect(keeper.calls, isEmpty);
  });
}
