import 'package:discere/external/inaturalist/request_memo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> requested;

  RequestMemo<String, int?> build({void Function(String)? onMemoHit}) =>
      RequestMemo(
        isWorthKeeping: (value) => value != null,
        onMemoHit: onMemoHit,
      );

  setUp(() => requested = <String>[]);

  Future<int?> Function() answering(String key, int? value) => () async {
    requested.add(key);
    return value;
  };

  test('the first call goes out, the second does not', () async {
    final memo = build();

    expect(await memo.fetch('a', answering('a', 1)), 1);
    expect(await memo.fetch('a', answering('a', 1)), 1);

    expect(requested, ['a']);
  });

  test('different keys are fetched separately', () async {
    final memo = build();

    await memo.fetch('a', answering('a', 1));
    await memo.fetch('b', answering('b', 2));

    expect(requested, ['a', 'b']);
  });

  test('concurrent callers share one request', () async {
    // The point of the in-flight table: enrichment resolves the same taxon
    // for several species at once, against an API that rate-limits.
    final memo = build();

    final results = await Future.wait([
      memo.fetch('a', answering('a', 1)),
      memo.fetch('a', answering('a', 1)),
      memo.fetch('a', answering('a', 1)),
    ]);

    expect(results, [1, 1, 1]);
    expect(requested, ['a']);
  });

  test('a result not worth keeping is fetched again next time', () async {
    // A failed lookup must not be inherited by the next caller.
    final memo = build();

    await memo.fetch('a', answering('a', null));
    await memo.fetch('a', answering('a', 7));

    expect(requested, ['a', 'a']);
    expect(memo['a'], 7);
  });

  test('a failed request leaves nothing behind', () async {
    final memo = build();

    await expectLater(
      memo.fetch('a', () async => throw StateError('boom')),
      throwsStateError,
    );
    expect(await memo.fetch('a', answering('a', 1)), 1);

    expect(requested, ['a']);
    expect(memo.containsKey('a'), isTrue);
  });

  test('a memo hit is reported, a fresh fetch is not', () async {
    final hits = <String>[];
    final memo = build(onMemoHit: hits.add);

    await memo.fetch('a', answering('a', 1));
    expect(hits, isEmpty);

    await memo.fetch('a', answering('a', 1));
    expect(hits, ['a']);
  });

  test('a remembered value can be read back and asked about', () async {
    final memo = build();

    expect(memo['a'], isNull);
    expect(memo.containsKey('a'), isFalse);

    memo.remember('a', 3);

    expect(memo['a'], 3);
    expect(memo.containsKey('a'), isTrue);
  });

  test('remembering something not worth keeping does nothing', () {
    final memo = build();

    memo.remember('a', null);

    expect(memo.containsKey('a'), isFalse);
  });
}
