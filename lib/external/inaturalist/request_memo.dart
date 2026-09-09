import 'dart:async';

/// Remembers what has already been fetched, and lets concurrent callers
/// asking for the same key share one request instead of racing.
///
/// The second half matters more than the first here. Enrichment resolves the
/// same taxon for several species at once; without the in-flight table each
/// of them would send its own request against an API that rate-limits.
class RequestMemo<K, V> {
  final Map<K, V> _completed = <K, V>{};
  final Map<K, Future<V>> _inFlight = <K, Future<V>>{};

  /// Whether a result is worth remembering. A failed lookup is not — the
  /// next caller should try again rather than inherit the failure.
  final bool Function(V value) _isWorthKeeping;

  /// Called when an answer comes from [_completed] rather than the network.
  final void Function(K key)? _onMemoHit;

  RequestMemo({
    required bool Function(V value) isWorthKeeping,
    void Function(K key)? onMemoHit,
  }) : _isWorthKeeping = isWorthKeeping,
       _onMemoHit = onMemoHit;

  V? operator [](K key) => _completed[key];

  bool containsKey(K key) => _completed.containsKey(key);

  void remember(K key, V value) {
    if (_isWorthKeeping(value)) _completed[key] = value;
  }

  Future<V> fetch(K key, Future<V> Function() request) {
    final completed = _completed[key];
    if (completed != null) {
      _onMemoHit?.call(key);
      return Future.value(completed);
    }

    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;

    final future = _run(key, request);
    _inFlight[key] = future;
    return future;
  }

  Future<V> _run(K key, Future<V> Function() request) async {
    try {
      final value = await request();
      remember(key, value);
      return value;
    } finally {
      unawaited(_inFlight.remove(key));
    }
  }
}
