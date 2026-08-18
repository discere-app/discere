import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

abstract class NetworkAvailability {
  bool get isOnline;

  /// Emits [true] when connectivity is gained, [false] when lost.
  Stream<bool> get onlineStatusChanges;

  Future<void> initialize();

  /// One-shot check, safe to call before [initialize]. True only when the
  /// active connection is confirmed unmetered (Wi-Fi/Ethernet) — cellular,
  /// VPN/Bluetooth-only, no connection, and anything unrecognized all report
  /// `false` so a large download is gated by default unless Wi-Fi is
  /// confirmed.
  Future<bool> isOnWifi();
}

/// Always reports online — used on platforms where connectivity detection is
/// not needed (web, desktop) and in tests.
class AlwaysOnlineNetworkAvailability implements NetworkAvailability {
  const AlwaysOnlineNetworkAvailability();

  @override
  bool get isOnline => true;

  @override
  Stream<bool> get onlineStatusChanges => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isOnWifi() async => true;
}

class ConnectivityNetworkAvailability implements NetworkAvailability {
  final Connectivity _connectivity;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  ConnectivityNetworkAvailability({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  @override
  bool get isOnline => _isOnline;

  @override
  Stream<bool> get onlineStatusChanges => _controller.stream;

  @override
  Future<void> initialize() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    final results = await _connectivity.checkConnectivity();
    _isOnline = _hasConnection(results);
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final online = _hasConnection(results);
      if (online == _isOnline) return;
      _isOnline = online;
      _controller.add(online);
    });
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }

  @override
  Future<bool> isOnWifi() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return true;
    final results = await _connectivity.checkConnectivity();
    return results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
  }

  static bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }
}
