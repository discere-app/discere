import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('activates cooldown after repeated retryable failures', () {
    final tracker = HostCooldownTracker(
      cooldownSteps: const [Duration(seconds: 15)],
    );

    tracker.recordRetryableFailure('example.org');
    tracker.recordRetryableFailure('example.org');
    expect(tracker.hasActiveCooldown, isFalse);

    tracker.recordRetryableFailure('example.org');

    final cooldown = tracker.activeCooldown;
    expect(cooldown, isNotNull);
    expect(cooldown!.host, 'example.org');
    expect(cooldown.remaining().inSeconds, greaterThanOrEqualTo(14));
  });

  test('clears cooldown after successful response', () {
    final tracker = HostCooldownTracker(
      cooldownSteps: const [Duration(seconds: 15)],
    );

    tracker.recordRetryableFailure('example.org');
    tracker.recordRetryableFailure('example.org');
    tracker.recordRetryableFailure('example.org');
    expect(tracker.hasActiveCooldown, isTrue);

    tracker.recordHttpResponse('example.org', 200);

    expect(tracker.hasActiveCooldown, isFalse);
  });

  test('uses a lower activation threshold for api.inaturalist.org', () {
    final tracker = HostCooldownTracker();

    tracker.recordRetryableFailure('api.inaturalist.org');
    expect(tracker.hasActiveCooldown, isFalse);

    tracker.recordRetryableFailure('api.inaturalist.org');
    expect(tracker.hasActiveCooldown, isTrue);
  });

  test('applies an immediate cooldown on rate limiting responses', () {
    final tracker = HostCooldownTracker();

    tracker.recordHttpResponse('api.inaturalist.org', 429);

    final cooldown = tracker.cooldownForHost('api.inaturalist.org');
    expect(cooldown, isNotNull);
    expect(cooldown!.remaining().inSeconds, greaterThanOrEqualTo(44));
  });
}
