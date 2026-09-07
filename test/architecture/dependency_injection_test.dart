/// Architecture test (ARCH-09) — no hidden collaborator defaults.
///
/// A constructor that defaults or falls back to a freshly built repository or
/// service makes the dependency invisible: the type says the collaborator is
/// optional while the object still opens a database. A caller that "just
/// constructs it" then bypasses the wiring entirely, and a test that forgets
/// to inject a fake silently talks to the real thing.
///
/// Repositories and services are the two suffixes this codebase gives real
/// structural meaning (persistence and business logic), so both are covered.
/// A stateless `const` strategy object with no collaborators of its own —
/// `DeckSerializationWorker` is the only one today — is deliberately not:
/// there is nothing to hide, and defaulting it costs a caller nothing.
///
/// Run with: flutter test test/architecture/dependency_injection_test.dart
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'arch_assertions.dart';

/// `_field = someParam ?? SomeRepository()` in an initializer list.
final _fallback = RegExp(r'\?\?\s*(?:const\s+)?[A-Z]\w*(?:Repository|Service)\(');

/// `SomeRepository param = const SomeRepository()` in a parameter list.
/// A bare `Type name =` (no `final`/`var`/`late`) only occurs there.
final _defaultValue = RegExp(
  r'^\s*[A-Z]\w*(?:Repository|Service)\??\s+\w+\s*=\s*(?:const\s+)?[A-Z]\w*'
  r'(?:Repository|Service)\(',
  multiLine: true,
);

void main() {
  test('constructors must not default or fall back to a collaborator', () {
    // The composition root is where collaborators are supposed to be built,
    // so a fallback there hides nothing — it is the wiring. BootstrapApp
    // takes an optional NotificationService as a test seam and builds the
    // real one once SharedPreferences exists, which is only inside
    // _setupCriticalServices; there is nowhere earlier to hoist it to.
    const allowedFiles = <String>{'lib/app/bootstrap/bootstrap_app.dart'};

    final violations = <String>[];
    var scannedFiles = 0;
    var scannedConstructors = 0;
    final constructorish = RegExp(r'^\s*(?:const\s+)?[A-Z]\w*[.(]', multiLine: true);

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final relativePath = entity.path.replaceAll('\\', '/');
      final src = entity.readAsStringSync();
      scannedFiles++;
      scannedConstructors += constructorish.allMatches(src).length;

      if (allowedFiles.any(relativePath.endsWith)) continue;

      for (final pattern in [_fallback, _defaultValue]) {
        for (final match in pattern.allMatches(src)) {
          final line = '\n'.allMatches(src.substring(0, match.start)).length + 1;
          violations.add('$relativePath:$line  ${match.group(0)!.trim()}');
        }
      }
    }

    expectScanFound(scannedFiles, 200, 'Dart files under lib/');
    expectScanFound(scannedConstructors, 500, 'constructor-shaped lines');

    expect(
      violations,
      isEmpty,
      reason:
          'ARCH-09: a collaborator is being defaulted instead of injected. '
          'Make the '
          'parameter `required` and build the instance in app/wiring/, so the '
          'dependency is visible in the type and there is one place that '
          'decides which instance everything shares.\n'
          'Violations:\n  ${violations.join('\n  ')}',
    );
  });
}
