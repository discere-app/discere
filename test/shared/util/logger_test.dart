import 'package:discere/shared/util/logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<({LogLevel level, String scope, String message})> persisted;

  setUp(() {
    persisted = [];
    Logger.configurePersistence(
      enabled: true,
      sink: (level, scope, message) async {
        persisted.add((level: level, scope: scope, message: message));
      },
    );
  });

  tearDown(() => Logger.configurePersistence(enabled: false));

  StackTrace stackOf(int frameCount) => StackTrace.fromString(
    [
      for (var i = 0; i < frameCount; i++) ...[
        '#$i      frame$i (package:discere/f.dart:$i:1)',
        '<asynchronous suspension>',
      ],
    ].join('\n'),
  );

  test('a message without error or stack trace is persisted unchanged', () {
    Logger.warn('Scope', 'plain message');

    expect(persisted.single.message, 'plain message');
  });

  test('appends the error type and text to the message', () {
    Logger.error('Scope', 'Lookup failed', error: StateError('boom'));

    expect(persisted.single.level, LogLevel.error);
    expect(
      persisted.single.message,
      'Lookup failed — StateError: Bad state: boom',
    );
  });

  test('cuts a long error text', () {
    Logger.warn('Scope', 'Lookup failed', error: Exception('x' * 2000));

    final message = persisted.single.message;
    expect(message, contains('x' * 400));
    expect(message, isNot(contains('x' * 600)));
    expect(message, endsWith('…'));
  });

  test('writes the stack frames indented on lines of their own, without '
      'asynchronous suspension markers', () {
    ScopedLogger(
      'Scope',
    ).warn('Lookup failed', error: StateError('boom'), stackTrace: stackOf(3));

    expect(persisted.single.message.split('\n'), [
      'Lookup failed — StateError: Bad state: boom',
      '    #0      frame0 (package:discere/f.dart:0:1)',
      '    #1      frame1 (package:discere/f.dart:1:1)',
      '    #2      frame2 (package:discere/f.dart:2:1)',
    ]);
  });

  test('keeps the first twelve frames and counts the rest', () {
    ScopedLogger('Scope').error('Lookup failed', stackTrace: stackOf(20));

    final lines = persisted.single.message.split('\n');
    expect(lines, hasLength(1 + 12 + 1));
    expect(lines[12], '    #11      frame11 (package:discere/f.dart:11:1)');
    expect(lines.last, '    … 8 more frames');
  });
}
