/// How many rows a reference-ID rewrite changed and dropped, per table (or
/// per preference key, for the ID lists kept outside the database).
class ReferenceIdRewriteReport {
  final _counts = <String, ({int rewritten, int dropped})>{};

  Map<String, ({int rewritten, int dropped})> get counts =>
      Map.unmodifiable(_counts);

  int get totalDropped =>
      _counts.values.fold(0, (sum, count) => sum + count.dropped);

  /// Adds to what [target] already recorded, so a table rewritten in two
  /// steps reports one line.
  void record(String target, {required int rewritten, required int dropped}) {
    final previous = _counts[target];
    _counts[target] = (
      rewritten: (previous?.rewritten ?? 0) + rewritten,
      dropped: (previous?.dropped ?? 0) + dropped,
    );
  }

  /// The targets with anything rewritten or dropped.
  @override
  String toString() {
    final lines = [
      for (final MapEntry(key: target, value: count) in _counts.entries)
        if (count.rewritten > 0 || count.dropped > 0)
          '$target: ${count.rewritten} rewritten, ${count.dropped} dropped',
    ];
    return lines.isEmpty ? 'nothing rewritten' : lines.join('; ');
  }
}
