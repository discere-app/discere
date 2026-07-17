/// Architecture tests — enforce module dependency rules using dart_arch_test.
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
/// Run with: flutter test test/architecture/module_dependency_test.dart
library;

import 'package:dart_arch_test/dart_arch_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DependencyGraph graph;

  setUpAll(() async {
    graph = await Collector.buildGraph('lib');
  });

  // ── Slice definitions ──────────────────────────────────────────────────────
  //
  // Each slice maps a name to a glob pattern relative to lib/.
  // theme and l10n are infrastructure — not included as slices so they are
  // implicitly allowed as targets from any module.

  group('Architecture – Slice isolation', () {
    test('all slices respect the allowed dependency matrix', () {
      defineSlices({
            'shared': 'shared/**',
            'external': 'external/**',
            'diagnostics': 'diagnostics/**',
            'catalog': 'catalog/**',
            'enrichment': 'enrichment/**',
            'learning': 'learning/**',
            'app': 'app/**',
          })
          .allowDependency('external', 'shared')
          .allowDependency('diagnostics', 'shared')
          .allowDependency('catalog', 'external')
          .allowDependency('catalog', 'shared')
          .allowDependency('enrichment', 'catalog')
          .allowDependency('enrichment', 'external')
          .allowDependency('enrichment', 'diagnostics')
          .allowDependency('enrichment', 'shared')
          .allowDependency('learning', 'catalog')
          .allowDependency('learning', 'enrichment')
          .allowDependency('learning', 'external')
          .allowDependency('learning', 'shared')
          .allowDependency('app', 'catalog')
          .allowDependency('app', 'enrichment')
          .allowDependency('app', 'external')
          .allowDependency('app', 'diagnostics')
          .allowDependency('app', 'learning')
          .allowDependency('app', 'shared')
          .enforceIsolation(graph);
    });
  });

  // ── Individual rules ───────────────────────────────────────────────────────

  group('Architecture – shared is the foundation', () {
    test('shared does not import external', () {
      shouldNotDependOn(
        filesMatching('shared/**'),
        filesMatching('external/**'),
        graph,
      );
    });

    test('shared does not import diagnostics', () {
      shouldNotDependOn(
        filesMatching('shared/**'),
        filesMatching('diagnostics/**'),
        graph,
      );
    });

    test('shared does not import catalog', () {
      shouldNotDependOn(
        filesMatching('shared/**'),
        filesMatching('catalog/**'),
        graph,
      );
    });

    test('shared does not import enrichment', () {
      shouldNotDependOn(
        filesMatching('shared/**'),
        filesMatching('enrichment/**'),
        graph,
      );
    });

    test('shared does not import learning', () {
      shouldNotDependOn(
        filesMatching('shared/**'),
        filesMatching('learning/**'),
        graph,
      );
    });
  });

  group('Architecture – external only talks to shared', () {
    test('external does not import catalog', () {
      shouldNotDependOn(
        filesMatching('external/**'),
        filesMatching('catalog/**'),
        graph,
      );
    });

    test('external does not import enrichment', () {
      shouldNotDependOn(
        filesMatching('external/**'),
        filesMatching('enrichment/**'),
        graph,
      );
    });

    test('external does not import learning', () {
      shouldNotDependOn(
        filesMatching('external/**'),
        filesMatching('learning/**'),
        graph,
      );
    });
  });

  group('Architecture – diagnostics only talks to shared', () {
    test('diagnostics does not import catalog', () {
      shouldNotDependOn(
        filesMatching('diagnostics/**'),
        filesMatching('catalog/**'),
        graph,
      );
    });

    test('diagnostics does not import enrichment', () {
      shouldNotDependOn(
        filesMatching('diagnostics/**'),
        filesMatching('enrichment/**'),
        graph,
      );
    });

    test('diagnostics does not import learning', () {
      shouldNotDependOn(
        filesMatching('diagnostics/**'),
        filesMatching('learning/**'),
        graph,
      );
    });
  });

  group('Architecture – catalog has no upward dependencies', () {
    test('catalog does not import enrichment', () {
      shouldNotDependOn(
        filesMatching('catalog/**'),
        filesMatching('enrichment/**'),
        graph,
      );
    });

    test('catalog does not import learning', () {
      shouldNotDependOn(
        filesMatching('catalog/**'),
        filesMatching('learning/**'),
        graph,
      );
    });
  });

  group('Architecture – enrichment stays below learning', () {
    test('enrichment does not import learning', () {
      shouldNotDependOn(
        filesMatching('enrichment/**'),
        filesMatching('learning/**'),
        graph,
      );
    });
  });

  group('Architecture – app is the composition root', () {
    test('app does not import itself cyclically', () {
      shouldBeFreeOfCycles(filesMatching('app/**'), graph);
    });
  });

  group('Architecture – no cycles', () {
    test('no circular dependencies within any slice', () {
      shouldBeFreeOfCycles(filesMatching('shared/**'), graph);
      shouldBeFreeOfCycles(filesMatching('external/**'), graph);
      shouldBeFreeOfCycles(filesMatching('diagnostics/**'), graph);
      shouldBeFreeOfCycles(filesMatching('catalog/**'), graph);
      shouldBeFreeOfCycles(filesMatching('enrichment/**'), graph);
      shouldBeFreeOfCycles(filesMatching('learning/**'), graph);
      shouldBeFreeOfCycles(filesMatching('app/**'), graph);
    });
  });
}
