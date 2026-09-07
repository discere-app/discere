import 'dart:async';

import 'package:discere/enrichment/queue/service/enrichment_lifecycle_coordinator.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNetworkAvailability implements NetworkAvailability {
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  bool isOnline = true;

  @override
  Stream<bool> get onlineStatusChanges => _controller.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isOnWifi() async => isOnline;

  void emit(bool online) {
    isOnline = online;
    _controller.add(online);
  }

  Future<void> close() => _controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeNetworkAvailability network;
  late List<String> events;
  late Completer<void>? blockEnterForeground;

  /// Every coordinator is torn down here rather than at the end of the test
  /// body: one that keeps its binding observer past a failing test would go
  /// on answering the next test's lifecycle events.
  EnrichmentLifecycleCoordinator register(
    EnrichmentLifecycleCoordinator coordinator,
  ) {
    addTearDown(coordinator.dispose);
    return coordinator;
  }

  EnrichmentLifecycleCoordinator build() => register(
    EnrichmentLifecycleCoordinator(
      networkAvailability: network,
      onEnterForeground: () async {
        events.add('enter');
        await blockEnterForeground?.future;
      },
      onLeaveForeground: () async => events.add('leave'),
      onNetworkOnline: () => events.add('online'),
    ),
  );

  /// Delivers a lifecycle state and waits for the transition it schedules.
  Future<void> send(
    EnrichmentLifecycleCoordinator coordinator,
    AppLifecycleState state,
  ) async {
    coordinator.handleAppLifecycleState(state);
    await coordinator.settled;
  }

  setUp(() {
    network = _FakeNetworkAvailability();
    events = <String>[];
    blockEnterForeground = null;
  });

  tearDown(() => network.close());

  test('starts in the foreground before any lifecycle event arrives', () {
    final coordinator = build();
    expect(coordinator.isInForeground, isTrue);
    expect(events, isEmpty);
  });

  test('paused leaves the foreground, resumed returns to it', () async {
    final coordinator = build()..watchAppLifecycle();

    await send(coordinator, AppLifecycleState.paused);
    expect(coordinator.isInForeground, isFalse);

    await send(coordinator, AppLifecycleState.resumed);
    expect(coordinator.isInForeground, isTrue);

    expect(events, ['leave', 'enter']);
  });

  test('detached is treated as leaving the foreground', () async {
    final coordinator = build()..watchAppLifecycle();

    await send(coordinator, AppLifecycleState.detached);

    expect(coordinator.isInForeground, isFalse);
    expect(events, ['leave']);
  });

  test('inactive and hidden change nothing', () async {
    final coordinator = build()..watchAppLifecycle();

    await send(coordinator, AppLifecycleState.inactive);
    await send(coordinator, AppLifecycleState.hidden);

    expect(coordinator.isInForeground, isTrue);
    expect(events, isEmpty);
  });

  test('repeating the state the app is already in does nothing', () async {
    final coordinator = build()..watchAppLifecycle();

    await send(coordinator, AppLifecycleState.paused);
    await send(coordinator, AppLifecycleState.paused);

    expect(events, ['leave']);
  });

  test(
    'signals arriving during a transition collapse to the final state',
    () async {
      blockEnterForeground = Completer<void>();
      final coordinator = build()..watchAppLifecycle();

      // Leave and come back, so the slow onEnterForeground is in flight.
      await send(coordinator, AppLifecycleState.paused);
      unawaited(send(coordinator, AppLifecycleState.resumed));
      await pumpEventQueue();
      expect(events, ['leave', 'enter']);

      // While it hangs, the app goes away and comes back again. Both are
      // queued behind the running transition; by the time it drains, the
      // app is in the foreground again — which is where it already was, so
      // neither callback should fire a second time.
      coordinator
        ..handleAppLifecycleState(AppLifecycleState.paused)
        ..handleAppLifecycleState(AppLifecycleState.resumed);
      blockEnterForeground!.complete();
      await coordinator.settled;
      await pumpEventQueue();

      expect(events, ['leave', 'enter']);
    },
  );

  test('a failing transition does not stall the ones behind it', () async {
    final coordinator = register(
      EnrichmentLifecycleCoordinator(
        networkAvailability: network,
        onEnterForeground: () async => events.add('enter'),
        onLeaveForeground: () async {
          events.add('leave');
          throw StateError('refresh failed');
        },
        onNetworkOnline: () => events.add('online'),
      ),
    )..watchAppLifecycle();

    await send(coordinator, AppLifecycleState.paused);
    await send(coordinator, AppLifecycleState.resumed);

    expect(events, ['leave', 'enter']);
  });

  test('regaining connectivity reports, losing it does not', () async {
    build().watchNetwork();

    network.emit(false);
    await pumpEventQueue();
    expect(events, isEmpty);

    network.emit(true);
    await pumpEventQueue();
    expect(events, ['online']);
  });

  test('nothing is reported after dispose', () async {
    final coordinator = build()
      ..watchNetwork()
      ..watchAppLifecycle()
      ..dispose();

    network.emit(true);
    await send(coordinator, AppLifecycleState.paused);
    await pumpEventQueue();

    expect(events, isEmpty);
    expect(coordinator.isInForeground, isTrue);
  });

  test('watching after dispose stays inert', () async {
    final coordinator = build()..dispose();

    coordinator
      ..watchNetwork()
      ..watchAppLifecycle();

    network.emit(true);
    await send(coordinator, AppLifecycleState.paused);
    await pumpEventQueue();

    expect(events, isEmpty);
  });

  test('the registered observer routes lifecycle changes through', () async {
    final coordinator = build()..watchAppLifecycle();

    // Drives the real binding, so this covers the wiring that `send` skips.
    // Only adjacent states: the binding rejects a jump across the sequence.
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      WidgetsBinding.instance.handleAppLifecycleStateChanged(state);
    }
    await coordinator.settled;

    expect(coordinator.isInForeground, isFalse);
    expect(events, ['leave']);
  });
}
