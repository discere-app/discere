import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class HostCooldownSnapshot {
  final String host;
  final DateTime activeUntil;

  const HostCooldownSnapshot({required this.host, required this.activeUntil});

  Duration remaining({DateTime? now}) {
    final remaining = activeUntil.difference(now ?? DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

class HostCooldownTracker extends ChangeNotifier {
  final Duration _failureWindow;
  final int _activationThreshold;
  final List<Duration> _cooldownSteps;
  final DateTime Function() _now;
  final Map<String, _HostCooldownState> _states =
      <String, _HostCooldownState>{};
  final Map<String, Timer> _expiryTimers = <String, Timer>{};

  HostCooldownTracker({
    Duration failureWindow = const Duration(seconds: 30),
    int activationThreshold = 3,
    List<Duration> cooldownSteps = const <Duration>[
      Duration(seconds: 15),
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 2),
    ],
    DateTime Function()? now,
  }) : _failureWindow = failureWindow,
       _activationThreshold = activationThreshold,
       _cooldownSteps = cooldownSteps,
       _now = now ?? DateTime.now;

  bool get hasActiveCooldown => activeCooldown != null;

  HostCooldownSnapshot? get activeCooldown {
    _expireInactiveCooldowns();
    HostCooldownSnapshot? latest;
    for (final entry in _states.entries) {
      final activeUntil = entry.value.activeUntil;
      if (activeUntil == null || !activeUntil.isAfter(_now())) continue;
      if (latest == null || activeUntil.isAfter(latest.activeUntil)) {
        latest = HostCooldownSnapshot(
          host: entry.key,
          activeUntil: activeUntil,
        );
      }
    }
    return latest;
  }

  Future<void> waitIfCoolingDown(String host) async {
    final cooldown = cooldownForHost(host);
    if (cooldown == null) return;
    final remaining = cooldown.remaining(now: _now());
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  HostCooldownSnapshot? cooldownForHost(String host) {
    _expireInactiveCooldowns();
    final state = _states[host];
    final activeUntil = state?.activeUntil;
    if (activeUntil == null || !activeUntil.isAfter(_now())) {
      return null;
    }
    return HostCooldownSnapshot(host: host, activeUntil: activeUntil);
  }

  void recordHttpResponse(String host, int statusCode) {
    if (statusCode == 429) {
      _recordDirectCooldown(host, _profileForHost(host).rateLimitCooldownSteps);
      return;
    }
    if (_isRetryableStatus(statusCode)) {
      recordRetryableFailure(
        host,
        cooldownSteps: _profileForHost(host).responseCooldownSteps,
      );
    } else {
      clearHost(host);
    }
  }

  void recordHttpError(String host, Object error) {
    if (_isRetryableError(error)) {
      recordRetryableFailure(
        host,
        cooldownSteps: _profileForHost(host).transportCooldownSteps,
      );
    } else {
      clearHost(host);
    }
  }

  void recordRetryableFailure(String host, {List<Duration>? cooldownSteps}) {
    final now = _now();
    final state = _states.putIfAbsent(host, _HostCooldownState.new);
    final profile = _profileForHost(host);
    final activeSteps = cooldownSteps ?? profile.responseCooldownSteps;
    final previousActiveUntil = state.activeUntil;

    if (state.lastFailureAt == null ||
        now.difference(state.lastFailureAt!) > _failureWindow) {
      state.retryableFailureCount = 1;
      state.cooldownActivationCount = 0;
    } else {
      state.retryableFailureCount += 1;
    }
    state.lastFailureAt = now;

    final threshold = profile.activationThreshold;
    if (state.retryableFailureCount < threshold) {
      return;
    }

    state.cooldownActivationCount += 1;
    final cooldownIndex = (state.cooldownActivationCount - 1).clamp(
      0,
      activeSteps.length - 1,
    );
    final nextActiveUntil = now.add(activeSteps[cooldownIndex]);
    if (previousActiveUntil == null ||
        nextActiveUntil.isAfter(previousActiveUntil)) {
      state.activeUntil = nextActiveUntil;
      _scheduleExpiry(host, nextActiveUntil);
      notifyListeners();
    }
  }

  void _recordDirectCooldown(String host, List<Duration> cooldownSteps) {
    final now = _now();
    final state = _states.putIfAbsent(host, _HostCooldownState.new);
    if (state.lastFailureAt == null ||
        now.difference(state.lastFailureAt!) > _failureWindow) {
      state.cooldownActivationCount = 0;
    }
    state.lastFailureAt = now;
    state.retryableFailureCount = _profileForHost(host).activationThreshold;
    state.cooldownActivationCount += 1;
    final index = (state.cooldownActivationCount - 1).clamp(
      0,
      cooldownSteps.length - 1,
    );
    state.activeUntil = now.add(cooldownSteps[index]);
    _scheduleExpiry(host, state.activeUntil!);
    notifyListeners();
  }

  void clearHost(String host) {
    final removed = _states.remove(host);
    _cancelExpiryTimer(host);
    if (removed?.activeUntil != null) {
      notifyListeners();
    }
  }

  @visibleForTesting
  void disposeTracker() {
    for (final timer in _expiryTimers.values) {
      timer.cancel();
    }
    _expiryTimers.clear();
    _states.clear();
    super.dispose();
  }

  void _expireInactiveCooldowns() {
    final now = _now();
    final expiredHosts = <String>[];
    for (final entry in _states.entries) {
      final activeUntil = entry.value.activeUntil;
      if (activeUntil != null && !activeUntil.isAfter(now)) {
        expiredHosts.add(entry.key);
      }
    }
    if (expiredHosts.isEmpty) return;
    for (final host in expiredHosts) {
      _states.remove(host);
      _cancelExpiryTimer(host);
    }
    notifyListeners();
  }

  void _scheduleExpiry(String host, DateTime activeUntil) {
    _cancelExpiryTimer(host);
    final delay = activeUntil.difference(_now());
    if (delay <= Duration.zero) {
      _expireInactiveCooldowns();
      return;
    }
    _expiryTimers[host] = Timer(delay, () {
      _expiryTimers.remove(host);
      _expireInactiveCooldowns();
    });
  }

  void _cancelExpiryTimer(String host) {
    _expiryTimers.remove(host)?.cancel();
  }

  static bool _isRetryableStatus(int statusCode) {
    return statusCode == 408 ||
        statusCode == 425 ||
        statusCode == 429 ||
        statusCode >= 500;
  }

  static bool _isRetryableError(Object error) {
    final typeName = error.runtimeType.toString();
    return error is TimeoutException ||
        error is http.ClientException ||
        typeName == 'SocketException' ||
        typeName == '_ClientSocketException';
  }

  HostCooldownProfile _profileForHost(String host) {
    if (host == 'api.inaturalist.org') {
      return const HostCooldownProfile(
        activationThreshold: 2,
        transportCooldownSteps: <Duration>[
          Duration(seconds: 10),
          Duration(seconds: 20),
          Duration(seconds: 45),
          Duration(seconds: 90),
        ],
        responseCooldownSteps: <Duration>[
          Duration(seconds: 15),
          Duration(seconds: 30),
          Duration(minutes: 1),
          Duration(minutes: 2),
        ],
        rateLimitCooldownSteps: <Duration>[
          Duration(seconds: 45),
          Duration(minutes: 2),
          Duration(minutes: 5),
          Duration(minutes: 10),
        ],
      );
    }
    if (host == 'www.inaturalist.org' ||
        host == 'inaturalist-open-data.s3.amazonaws.com') {
      return const HostCooldownProfile(
        activationThreshold: 2,
        transportCooldownSteps: <Duration>[
          Duration(seconds: 8),
          Duration(seconds: 20),
          Duration(seconds: 45),
          Duration(seconds: 90),
        ],
        responseCooldownSteps: <Duration>[
          Duration(seconds: 12),
          Duration(seconds: 25),
          Duration(seconds: 45),
          Duration(minutes: 2),
        ],
        rateLimitCooldownSteps: <Duration>[
          Duration(seconds: 30),
          Duration(seconds: 90),
          Duration(minutes: 3),
          Duration(minutes: 6),
        ],
      );
    }
    if (host == 'raw.githubusercontent.com') {
      return const HostCooldownProfile(
        activationThreshold: 2,
        transportCooldownSteps: <Duration>[
          Duration(seconds: 20),
          Duration(seconds: 45),
          Duration(minutes: 2),
          Duration(minutes: 4),
        ],
        responseCooldownSteps: <Duration>[
          Duration(seconds: 20),
          Duration(seconds: 45),
          Duration(minutes: 2),
          Duration(minutes: 4),
        ],
        rateLimitCooldownSteps: <Duration>[
          Duration(minutes: 1),
          Duration(minutes: 3),
          Duration(minutes: 6),
          Duration(minutes: 10),
        ],
      );
    }
    return HostCooldownProfile(
      activationThreshold: _activationThreshold,
      transportCooldownSteps: _cooldownSteps,
      responseCooldownSteps: _cooldownSteps,
      rateLimitCooldownSteps: _cooldownSteps,
    );
  }
}

class HostCooldownProfile {
  final int activationThreshold;
  final List<Duration> transportCooldownSteps;
  final List<Duration> responseCooldownSteps;
  final List<Duration> rateLimitCooldownSteps;

  const HostCooldownProfile({
    required this.activationThreshold,
    required this.transportCooldownSteps,
    required this.responseCooldownSteps,
    required this.rateLimitCooldownSteps,
  });
}

class _HostCooldownState {
  DateTime? lastFailureAt;
  int retryableFailureCount = 0;
  int cooldownActivationCount = 0;
  DateTime? activeUntil;
}
