/// Ensures user-facing text goes through AppLocalizations / the ARB files
/// rather than being hardcoded or leaking raw (English-only) exception text.
///
/// Line/regex-based scanning can't perfectly distinguish user-facing strings
/// from internal ones, so this only catches the common, obvious cases — a
/// maintained allowlist covers legitimate exceptions, following the same
/// approach as logging_convention_test.dart.
///
/// Run with: flutter test test/architecture/l10n_convention_test.dart
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Returns the text of every `Text(...)` call in [src] (the full argument
/// list, matched by paren-balance so multi-line calls are captured whole),
/// paired with the 1-based line its `Text(` token starts on.
Iterable<({String call, int line})> _textCalls(String src) sync* {
  final opener = RegExp(r'\bText\(');
  for (final match in opener.allMatches(src)) {
    var depth = 0;
    var end = match.end - 1; // index of the opening '('
    for (var i = end; i < src.length; i++) {
      if (src[i] == '(') depth++;
      if (src[i] == ')') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    final line = '\n'.allMatches(src.substring(0, match.start)).length + 1;
    yield (call: src.substring(match.start, end + 1), line: line);
  }
}

void main() {
  final libDir = Directory('lib');

  test('Text() must not be given a hardcoded string literal', () {
    // A pure string literal (no `$` interpolation at all) passed straight to
    // Text(...) is always hardcoded UI copy — move it into the ARB files and
    // read it via context.loc.
    final pattern = RegExp('''^\\(\\s*(?:'[^'\$]*'|"[^"\$]*")\\s*[,)]''');

    const allowedFiles = <String>{};

    final violations = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final relativePath = entity.path.replaceAll('\\', '/');
      if (allowedFiles.any((allowed) => relativePath.endsWith(allowed))) {
        continue;
      }

      final src = entity.readAsStringSync();
      for (final call in _textCalls(src)) {
        if (pattern.hasMatch(call.call.substring(4))) {
          violations.add('$relativePath:${call.line}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Text() was given a hardcoded string literal instead of a '
          'context.loc.* value. Add the copy to lib/l10n/*.arb instead.\n'
          'Violations:\n  ${violations.join('\n  ')}',
    );
  });

  test(
    'caught errors must not be stringified straight into localized text',
    () {
      // e.g. context.loc.errorSaveImage(e.toString()) — including the
      // argument list wrapping onto following lines. AppException.message and
      // Object.toString() are English-only and meant for logs/diagnostics.
      // Use AppExceptionLocalization.describeError(error) instead, which maps
      // the exception's type to a localized string.
      final tostringIntoLoc = RegExp(
        r'\.loc\.\w+\(\s*\w+\.toString\(\)',
        dotAll: true,
      );

      // e.g. Text('$error') / Text('$e') — a raw exception rendered directly.
      final rawErrorText = RegExp(
        '''^\\(\\s*(?:'\\\$(?:error|e)'|"\\\$(?:error|e)")''',
      );

      // e.g. Text('${loc.error}: ${snapshot.error}') — the label is
      // localized (or the surrounding text hardcoded) but the value
      // interpolated in is a raw exception. `${loc.error}` /
      // `${context.loc.error}` (the localized "Error:" label itself) and
      // `${loc.describeError(...)}` are fine — only a bare `error`/`e`, or a
      // `<something>.error` accessor not already routed through
      // `loc`/`describeError`, counts as a violation.
      final interpolationGroup = RegExp(r'\$\{([^}]*)\}');
      bool hasRawErrorInterpolation(String call) {
        for (final group in interpolationGroup.allMatches(call)) {
          final expr = group.group(1)!.trim();
          if (expr.contains('describeError(')) continue;
          if (expr == 'error' || expr == 'e') return true;
          final accessor = RegExp(r'(\w+)\.error$').firstMatch(expr);
          if (accessor != null && accessor.group(1) != 'loc') return true;
        }
        return false;
      }

      const allowedFiles = <String>{};

      final violations = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;

        final relativePath = entity.path.replaceAll('\\', '/');
        if (allowedFiles.any((allowed) => relativePath.endsWith(allowed))) {
          continue;
        }

        final src = entity.readAsStringSync();

        for (final match in tostringIntoLoc.allMatches(src)) {
          final line =
              '\n'.allMatches(src.substring(0, match.start)).length + 1;
          violations.add('$relativePath:$line');
        }

        for (final call in _textCalls(src)) {
          final body = call.call.substring(4);
          if (rawErrorText.hasMatch(body) ||
              hasRawErrorInterpolation(call.call)) {
            violations.add('$relativePath:${call.line}');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Found a raw exception string flowing into user-facing text. Use '
            'AppExceptionLocalization.describeError(error) '
            '(lib/shared/extensions/app_exception_localization.dart) instead.\n'
            'Violations:\n  ${violations.join('\n  ')}',
      );
    },
  );
}
