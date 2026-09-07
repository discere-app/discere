import 'dart:async';

import 'package:discere/shared/service/network_availability.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/widgets.dart';

/// Turns the two noisy platform signals the enrichment queue reacts to —
/// app foreground/background transitions and network availability — into the
/// three decisions it actually makes: resume, back off, retry now.
///
/// The queue service would otherwise carry the bookkeeping those signals
/// need, which is not queue policy: `AppLifecycleState` delivers `inactive`
/// and `hidden` alongside the two states that matter, fires repeatedly for
/// the same effective state, and can arrive while a previous transition is
/// still running. Collapsing that into [isInForeground] plus a pair of
/// callbacks leaves the service deciding *what* to do on a transition,
/// without also tracking *whether* one happened.
class EnrichmentLifecycleCoordinator {
  static final _log = Logger.forType(EnrichmentLifecycleCoordinator);

  final NetworkAvailability _networkAvailability;
  final Future<void> Function() _onEnterForeground;
  final Future<void> Function() _onLeaveForeground;
  final void Function() _onNetworkOnline;

  _LifecycleObserver? _observer;
  StreamSubscription<bool>? _networkSubscription;

  /// Transitions run one at a time. Each is asynchronous (it refreshes state
  /// and may start the runner), and the platform can deliver the next state
  /// change long before the previous transition has finished — running them
  /// concurrently would interleave two passes over the same queue state.
  Future<void> _transition = Future.value();

  /// The state transitions have actually been applied up to, versus the one
  /// most recently reported. They differ while a transition is in flight, and
  /// comparing them is what collapses a burst of signals into a single
  /// effective change.
  bool _isInForeground = true;
  bool _targetForeground = true;

  bool _disposed = false;

  EnrichmentLifecycleCoordinator({
    required NetworkAvailability networkAvailability,
    required Future<void> Function() onEnterForeground,
    required Future<void> Function() onLeaveForeground,
    required void Function() onNetworkOnline,
  }) : _networkAvailability = networkAvailability,
       _onEnterForeground = onEnterForeground,
       _onLeaveForeground = onLeaveForeground,
       _onNetworkOnline = onNetworkOnline;

  /// Whether the app is currently in the foreground, as far as completed
  /// transitions are concerned. Starts optimistic: a service constructed
  /// while the app is running has had no lifecycle event to learn from yet,
  /// and treating that as backgrounded would start a keepalive notification
  /// for an app the user is looking at.
  bool get isInForeground => _isInForeground;

  /// Starts reacting to connectivity changes.
  ///
  /// Separate from [watchAppLifecycle] so the owner decides when each source
  /// goes live — the two are independent, and the queue's startup sequence
  /// has work it wants done between them.
  void watchNetwork() {
    if (_disposed) return;
    _networkSubscription = _networkAvailability.onlineStatusChanges.listen(
      _handleNetworkStatusChanged,
    );
  }

  /// Starts reacting to app foreground/background transitions.
  ///
  /// A missing or already-torn-down [WidgetsBinding] is not an error here:
  /// the queue runs in tests and background entrypoints that have no widget
  /// tree, and there it simply never leaves the foreground.
  void watchAppLifecycle() {
    if (_disposed) return;
    try {
      final observer = _LifecycleObserver(handleAppLifecycleState);
      WidgetsBinding.instance.addObserver(observer);
      _observer = observer;
    } catch (_) {
      _observer = null;
    }
  }

  void dispose() {
    _disposed = true;
    final observer = _observer;
    if (observer != null) {
      try {
        WidgetsBinding.instance.removeObserver(observer);
      } catch (_) {
        // Ignore if the binding is already gone.
      }
      _observer = null;
    }
    _networkSubscription?.cancel();
    _networkSubscription = null;
  }

  /// The coordinator's input for app lifecycle changes. Public because the
  /// observer registered by [watchAppLifecycle] is a two-line adapter around
  /// it, and driving it directly is the only way to exercise the transition
  /// logic without a widget binding.
  @visibleForTesting
  void handleAppLifecycleState(AppLifecycleState state) {
    _log.debug('Lifecycle state changed: $state');
    switch (state) {
      case AppLifecycleState.resumed:
        _scheduleTransition(true);
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _scheduleTransition(false);
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _scheduleTransition(bool foreground) {
    _targetForeground = foreground;
    _transition = _transition
        .then((_) async {
          if (_disposed) return;

          // Read the target rather than the captured argument: signals that
          // arrived while earlier transitions ran have already updated it,
          // so the queue only ever moves to the state the app is in now.
          final nextForeground = _targetForeground;
          if (nextForeground == _isInForeground) return;

          _isInForeground = nextForeground;
          if (nextForeground) {
            await _onEnterForeground();
          } else {
            await _onLeaveForeground();
          }
        })
        // Caught here rather than by the next link in the chain, so a failed
        // transition is reported when it fails instead of surfacing as an
        // unhandled async error whenever no further transition follows it.
        // Either way the chain keeps running: one bad transition must not
        // leave the queue stuck in the state it was trying to leave.
        .catchError((Object error, StackTrace stackTrace) {
          _log.warn('Lifecycle transition failed: $error');
        });
  }

  void _handleNetworkStatusChanged(bool isOnline) {
    if (_disposed) return;
    _log.debug('Network status changed: ${isOnline ? 'online' : 'offline'}');
    if (isOnline) {
      _onNetworkOnline();
    }
    // Going offline needs no action: the running workers' shouldStop turns
    // true at their next loop iteration and they wind down on their own.
  }

  /// Completes once every transition scheduled so far has been applied.
  /// Tests need it because a lifecycle signal is answered asynchronously —
  /// without it they would assert against the state before the transition.
  @visibleForTesting
  Future<void> get settled => _transition;
}

/// Exists only to receive [didChangeAppLifecycleState]; the rest of
/// [WidgetsBindingObserver] would be noise on the coordinator itself.
class _LifecycleObserver with WidgetsBindingObserver {
  final void Function(AppLifecycleState) _onStateChanged;

  _LifecycleObserver(this._onStateChanged);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _onStateChanged(state);
  }
}
