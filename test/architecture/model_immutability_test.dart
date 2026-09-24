/// Architecture test (ARCH-10) — models are immutable.
///
/// A model travels through providers, `ChangeNotifier`s and isolate
/// boundaries. A public field that can be assigned along the way is a change
/// nobody asked for and nobody saved, and it surfaces as "why did the deck
/// name change without anyone pressing save" rather than as a failure at the
/// point of the mistake.
///
/// The rule is therefore about *public, assignable* fields. It says nothing
/// about deep immutability: a `final List` can still have things added to
/// it, and catching that needs types this codebase does not use. What it
/// does catch is the cheap and common mistake.
///
/// Private mutable state is untouched by this — a model that caches
/// something behind a getter is not what this rule is about.
///
/// Run with: flutter test test/architecture/model_immutability_test.dart
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'arch_assertions.dart';

/// Directories whose contents count as models. The slices agree on this
/// naming, so the rule follows the folder rather than a list of files.
bool _isModel(String path) =>
    path.contains('/model/') && path.endsWith('.dart') && !path.endsWith('.g.dart');

/// A field declaration that can be assigned after construction: no `final`,
/// no `const`, not a getter. Matched on the declaration line, which is how
/// these are written throughout `lib/`.
final _mutableField = RegExp(
  r'^  (?!final |const |static |late final )'
  r'([A-Z][\w<>,.]*\??|int\??|double\??|bool\??|num\??|String\??)'
  r'\s+([a-z][\w]*)\s*(=\s*[^;>][^;]*)?;\s*$',
);

/// `String get x => y;` and `Foo get x { … }` are not fields.
final _getter = RegExp(r'\bget\s+[a-z]');

void main() {
  test('models have no assignable public fields', () {
    final violations = <String>[];
    var scannedFiles = 0;
    var recognisedFields = 0;

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (!_isModel(path)) continue;

      scannedFiles++;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (_getter.hasMatch(line)) continue;
        if (RegExp(r'^  final |^  const ').hasMatch(line)) recognisedFields++;
        final match = _mutableField.firstMatch(line);
        if (match == null) continue;
        // `_private` state is the class's own business.
        if (match.group(2)!.startsWith('_')) continue;
        violations.add('$path:${i + 1}: ${line.trim()}');
      }
    }

    expectScanFound(scannedFiles, 20, 'model files under lib/');
    expectScanFound(recognisedFields, 100, 'final fields');

    expectNoNewViolations(
      'arch-10',
      violations,
      reason:
          'ARCH-10: make the field final and give the class a copyWith (or a '
          'narrower named method) for the change the caller actually wants.\n'
          'A model handed through a provider must not change under the code '
          'holding it.',
    );
  });
}
