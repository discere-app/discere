/// Runs [task] for each item in [items] with at most [maxConcurrent] parallel
/// executions. Returns a list of results in the same order as [items].
Future<List<R>> runWithConcurrency<T, R>(
  List<T> items, {
  required int maxConcurrent,
  required Future<R> Function(T item) task,
}) async {
  if (items.isEmpty) return [];

  final results = List<R?>.filled(items.length, null);
  var nextIndex = 0;

  Future<void> worker() async {
    while (true) {
      final currentIndex = nextIndex;
      if (currentIndex >= items.length) return;
      nextIndex++;
      results[currentIndex] = await task(items[currentIndex]);
    }
  }

  final workerCount = items.length < maxConcurrent
      ? items.length
      : maxConcurrent;
  await Future.wait(List.generate(workerCount, (_) => worker()));

  return results.cast<R>();
}

/// Runs [task] for each item in [items] with at most [maxConcurrent] parallel
/// executions. Unlike [runWithConcurrency], this variant does not collect
/// results and uses a simpler internal representation.
Future<void> runConcurrently<T>(
  List<T> items, {
  required int maxConcurrent,
  required Future<void> Function(T item) task,
  bool Function()? isCancelled,
}) async {
  if (items.isEmpty) return;

  var nextIndex = 0;

  Future<void> worker() async {
    while (true) {
      if (isCancelled?.call() ?? false) return;
      final currentIndex = nextIndex;
      if (currentIndex >= items.length) return;
      nextIndex++;
      await task(items[currentIndex]);
    }
  }

  final workerCount = items.length < maxConcurrent
      ? items.length
      : maxConcurrent;
  await Future.wait(List.generate(workerCount, (_) => worker()));
}

/// Runs [task] for each item with optional throttling between sequential
/// requests.
///
/// When [requestSpacing] is null/zero or [maxConcurrent] > 1, falls back to
/// [runConcurrently]. When [maxConcurrent] is 1 and [requestSpacing] is set,
/// processes items sequentially with a delay between each.
Future<void> runThrottled<T>(
  List<T> items, {
  required int maxConcurrent,
  Duration? requestSpacing,
  required Future<void> Function(T item) task,
  bool Function()? isCancelled,
}) async {
  if (items.isEmpty) return;

  if (requestSpacing == null ||
      requestSpacing.inMilliseconds <= 0 ||
      maxConcurrent > 1) {
    await runConcurrently(
      items,
      maxConcurrent: maxConcurrent,
      task: task,
      isCancelled: isCancelled,
    );
    return;
  }

  var isFirst = true;
  for (final item in items) {
    if (isCancelled?.call() ?? false) return;
    if (!isFirst) await Future.delayed(requestSpacing);
    isFirst = false;
    await task(item);
  }
}
