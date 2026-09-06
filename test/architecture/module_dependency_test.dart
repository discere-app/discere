/// Architecture tests — enforce the slice dependency matrix.
///
/// Allowed dependency matrix:
///   shared        → (nothing from discere)
///   external      → shared
///   diagnostics   → shared
///   catalog       → external, shared
///   enrichment    → catalog, external, diagnostics, shared
///   learning      → catalog, enrichment, external, shared
///   app           → catalog, enrichment, external, diagnostics, learning, shared
///
/// `theme/` and `l10n/` are infrastructure rather than slices: they are not
/// listed below, so nothing constrains who imports them.
///
/// Run with: flutter test test/architecture/module_dependency_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'arch_assertions.dart';
import 'import_graph.dart';

/// Slice name → glob over `lib/`-relative paths.
const _slices = <String, String>{
  'shared': 'shared/**',
  'external': 'external/**',
  'diagnostics': 'diagnostics/**',
  'catalog': 'catalog/**',
  'enrichment': 'enrichment/**',
  'learning': 'learning/**',
  'app': 'app/**',
};

/// Slice → the slices it may reference. Anything absent is forbidden, so a
/// new slice starts fully isolated and has to earn each edge explicitly.
const _allowedDependencies = <String, Set<String>>{
  'shared': {},
  'external': {'shared'},
  'diagnostics': {'shared'},
  'catalog': {'external', 'shared'},
  'enrichment': {'catalog', 'external', 'diagnostics', 'shared'},
  'learning': {'catalog', 'enrichment', 'external', 'shared'},
  'app': {
    'catalog',
    'enrichment',
    'external',
    'diagnostics',
    'learning',
    'shared',
  },
};

void main() {
  final graph = buildImportGraph();

  group('Architecture – the scan itself', () {
    test('sees the source tree', () {
      expectScanFound(graph.length, 200, 'Dart files under lib/');
      expectScanFound(edgeCount(graph), 700, 'in-project import/export edges');
    });

    test('every slice pattern still matches files', () {
      for (final entry in _slices.entries) {
        expectScanFound(
          filesMatching(graph, entry.value).length,
          3,
          'files in slice "${entry.key}" (${entry.value})',
        );
      }
    });
  });

  group('Architecture – slice dependency matrix', () {
    for (final source in _slices.keys) {
      for (final target in _slices.keys) {
        if (source == target) continue;
        if (_allowedDependencies[source]!.contains(target)) continue;

        test('$source does not import $target', () {
          final violations = forbiddenImports(
            graph,
            from: _slices[source]!,
            to: _slices[target]!,
          );
          expect(
            violations,
            isEmpty,
            reason:
                '"$source" may not depend on "$target" — see the matrix at '
                'the top of this file and in CLAUDE.md.\n'
                'Either move the code so the dependency points the allowed '
                'way, or invert it with a port interface in the lower slice '
                'plus an adapter in app/wiring/ (see enrichment_wiring.dart '
                'for the established pattern).\n'
                'Violations:\n  ${violations.join('\n  ')}',
          );
        });
      }
    }
  });

  group('Architecture – no cycles', () {
    for (final entry in _slices.entries) {
      test('no import cycle within ${entry.key}', () {
        final cycles = importCycles(graph, within: entry.value);
        expect(
          cycles,
          isEmpty,
          reason:
              'Import cycle inside "${entry.key}". One file per cycle is '
              'reported, not every cycle through it.\n'
              'Cycles:\n  ${cycles.join('\n  ')}',
        );
      });
    }
  });
}
