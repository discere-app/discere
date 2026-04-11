/// Architecture tests — enforce module dependency rules using dart_arch_test.
///
/// Allowed dependency matrix:
///   shared       → (nothing from discere)
///   catalog      → shared
///   enrichment   → catalog, shared
///   application  → catalog, enrichment, shared
///   learning     → catalog, enrichment, application, shared
///   app          → catalog, enrichment, application, learning, shared
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
            'catalog': 'catalog/**',
            'enrichment': 'enrichment/**',
            'application': 'application/**',
            'learning': 'learning/**',
            'app': 'app/**',
          })
          .allowDependency('catalog', 'shared')
          .allowDependency('enrichment', 'catalog')
          .allowDependency('enrichment', 'shared')
          .allowDependency('application', 'catalog')
          .allowDependency('application', 'enrichment')
          .allowDependency('application', 'shared')
          .allowDependency('learning', 'catalog')
          .allowDependency('learning', 'enrichment')
          .allowDependency('learning', 'application')
          .allowDependency('learning', 'shared')
          .allowDependency('app', 'catalog')
          .allowDependency('app', 'enrichment')
          .allowDependency('app', 'application')
          .allowDependency('app', 'learning')
          .allowDependency('app', 'shared')
          .enforceIsolation(graph);
    });
  });

  // ── Individual rules ───────────────────────────────────────────────────────

  group('Architecture – shared is the foundation', () {
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

    test('shared does not import application', () {
      shouldNotDependOn(
        filesMatching('shared/**'),
        filesMatching('application/**'),
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

  group('Architecture – catalog has no upward dependencies', () {
    test('catalog does not import enrichment', () {
      shouldNotDependOn(
        filesMatching('catalog/**'),
        filesMatching('enrichment/**'),
        graph,
      );
    });

    test('catalog does not import application', () {
      shouldNotDependOn(
        filesMatching('catalog/**'),
        filesMatching('application/**'),
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

  group('Architecture – enrichment stays below application and learning', () {
    test('enrichment does not import application', () {
      shouldNotDependOn(
        filesMatching('enrichment/**'),
        filesMatching('application/**'),
        graph,
      );
    });

    test('enrichment does not import learning', () {
      shouldNotDependOn(
        filesMatching('enrichment/**'),
        filesMatching('learning/**'),
        graph,
      );
    });
  });

  group('Architecture – application does not import learning', () {
    test('application does not import learning', () {
      shouldNotDependOn(
        filesMatching('application/**'),
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
      shouldBeFreeOfCycles(filesMatching('catalog/**'), graph);
      shouldBeFreeOfCycles(filesMatching('enrichment/**'), graph);
      shouldBeFreeOfCycles(filesMatching('application/**'), graph);
      shouldBeFreeOfCycles(filesMatching('learning/**'), graph);
      shouldBeFreeOfCycles(filesMatching('app/**'), graph);
    });
  });
}
