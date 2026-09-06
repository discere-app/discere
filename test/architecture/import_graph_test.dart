/// Tests for the architecture helpers themselves.
///
/// The rules in this directory are only as trustworthy as the scanner under
/// them: a graph builder that silently returns nothing, or a ratchet that
/// only fails in one direction, turns every rule green without checking
/// anything. The vacuity guards in each rule file catch that at the codebase
/// level; this file pins the behaviour directly, against fixtures small
/// enough to reason about.
///
/// Run with: flutter test test/architecture/import_graph_test.dart
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'arch_assertions.dart';
import 'import_graph.dart';

/// Writes [files] into a throwaway directory and returns its real path.
///
/// Resolved rather than raw, because `systemTemp` is a symlink on macOS and
/// the scanner recovers `lib/`-relative paths by stripping the root prefix.
String _fixture(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('arch_import_graph_');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final entry in files.entries) {
    final file = File('${dir.path}/${entry.key}')
      ..parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  return dir.resolveSymbolicLinksSync();
}

String _imports(List<String> targets) =>
    targets.map((t) => "import 'package:discere/$t';").join('\n');

void main() {
  group('globToRegExp', () {
    test('** spans directories, * stops at a separator', () {
      final deep = globToRegExp('shared/**');
      expect(deep.hasMatch('shared/util/logger.dart'), isTrue);
      expect(deep.hasMatch('catalog/util/logger.dart'), isFalse);

      final shallow = globToRegExp('shared/*');
      expect(shallow.hasMatch('shared/logger.dart'), isTrue);
      expect(shallow.hasMatch('shared/util/logger.dart'), isFalse);
    });

    test('a leading **/ also matches at the root', () {
      final pattern = globToRegExp('**/repository/**');
      expect(pattern.hasMatch('catalog/repository/species.dart'), isTrue);
      expect(pattern.hasMatch('a/b/c/repository/x.dart'), isTrue);
      expect(pattern.hasMatch('repository/x.dart'), isTrue);
      expect(pattern.hasMatch('catalog/service/species.dart'), isFalse);
    });

    test('anchors at both ends', () {
      expect(globToRegExp('app/**').hasMatch('lib/app/main.dart'), isFalse);

      final page = globToRegExp('*_page.dart');
      expect(page.hasMatch('deck_page.dart'), isTrue);
      expect(page.hasMatch('deck_page.dart.bak'), isFalse);
    });
  });

  group('buildImportGraph', () {
    test('records imports and exports, ignores everything else', () {
      final root = _fixture({
        'a.dart': """
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:discere/b.dart';
export 'package:discere/c.dart';
// import 'package:discere/d.dart';
""",
        'b.dart': '',
        'c.dart': '',
        'd.dart': '',
        'notes.txt': "import 'package:discere/b.dart';",
      });

      final graph = buildImportGraph(root: root);

      expect(graph.keys, containsAll(<String>['a.dart', 'b.dart', 'c.dart']));
      expect(graph.keys, isNot(contains('notes.txt')));
      expect(graph['a.dart'], {'b.dart', 'c.dart'});
      expect(graph['b.dart'], isEmpty);
      expect(edgeCount(graph), 2);
    });

    test('keeps nested paths relative to the root', () {
      final root = _fixture({
        'catalog/repository/species.dart': _imports([
          'shared/util/logger.dart',
        ]),
        'shared/util/logger.dart': '',
      });

      final graph = buildImportGraph(root: root);

      expect(graph['catalog/repository/species.dart'], {
        'shared/util/logger.dart',
      });
    });
  });

  group('forbiddenImports', () {
    late String root;

    setUp(() {
      root = _fixture({
        'app/home_page.dart': _imports([
          'catalog/repository/species.dart',
          'catalog/service/species.dart',
        ]),
        'app/settings_page.dart': _imports(['catalog/repository/species.dart']),
        'catalog/service/species.dart': _imports([
          'catalog/repository/species.dart',
        ]),
        'catalog/repository/species.dart': '',
      });
    });

    test('reports every offending edge, sorted', () {
      final violations = forbiddenImports(
        buildImportGraph(root: root),
        from: 'app/**',
        to: '**/repository/**',
      );

      expect(violations, [
        'app/home_page.dart -> catalog/repository/species.dart',
        'app/settings_page.dart -> catalog/repository/species.dart',
      ]);
    });

    test('except exempts source files by pattern', () {
      final violations = forbiddenImports(
        buildImportGraph(root: root),
        from: 'app/**',
        to: '**/repository/**',
        except: ['app/settings_page.dart'],
      );

      expect(violations, [
        'app/home_page.dart -> catalog/repository/species.dart',
      ]);
    });

    test('a service reaching its own repository is not an app violation', () {
      final violations = forbiddenImports(
        buildImportGraph(root: root),
        from: 'app/**',
        to: '**/repository/**',
        except: ['app/**'],
      );

      expect(violations, isEmpty);
    });
  });

  group('importCycles', () {
    test('finds a two-file cycle', () {
      final root = _fixture({
        'catalog/a.dart': _imports(['catalog/b.dart']),
        'catalog/b.dart': _imports(['catalog/a.dart']),
      });

      final cycles = importCycles(
        buildImportGraph(root: root),
        within: 'catalog/**',
      );

      expect(cycles, hasLength(1));
      expect(cycles.single, contains('catalog/a.dart'));
      expect(cycles.single, contains('catalog/b.dart'));
    });

    test('finds a longer cycle', () {
      final root = _fixture({
        'catalog/a.dart': _imports(['catalog/b.dart']),
        'catalog/b.dart': _imports(['catalog/c.dart']),
        'catalog/c.dart': _imports(['catalog/a.dart']),
      });

      expect(
        importCycles(buildImportGraph(root: root), within: 'catalog/**'),
        hasLength(1),
      );
    });

    test('a chain without a back edge is not a cycle', () {
      final root = _fixture({
        'catalog/a.dart': _imports(['catalog/b.dart', 'catalog/c.dart']),
        'catalog/b.dart': _imports(['catalog/c.dart']),
        'catalog/c.dart': '',
      });

      expect(
        importCycles(buildImportGraph(root: root), within: 'catalog/**'),
        isEmpty,
      );
    });

    test('ignores a cycle that leaves the scope', () {
      final root = _fixture({
        'catalog/a.dart': _imports(['learning/b.dart']),
        'learning/b.dart': _imports(['catalog/a.dart']),
      });

      expect(
        importCycles(buildImportGraph(root: root), within: 'catalog/**'),
        isEmpty,
      );
    });
  });

  group('expectScanFound', () {
    test('passes at or above the floor', () {
      expect(() => expectScanFound(10, 10, 'things'), returnsNormally);
      expect(() => expectScanFound(11, 10, 'things'), returnsNormally);
    });

    test('fails below the floor', () {
      expect(
        () => expectScanFound(0, 10, 'things'),
        throwsA(isA<TestFailure>()),
      );
    });
  });

  group('expectNoNewViolations', () {
    late String store;

    setUp(() {
      store = _fixture({'rule.txt': 'known-a\nknown-b\n'});
    });

    void run(List<String> violations) => expectNoNewViolations(
      'rule',
      violations,
      reason: 'test rule',
      storeDir: store,
    );

    test('passes when the violations match the baseline exactly', () {
      expect(() => run(['known-a', 'known-b']), returnsNormally);
    });

    test('fails on a violation that is not in the baseline', () {
      expect(
        () => run(['known-a', 'known-b', 'brand-new']),
        throwsA(isA<TestFailure>()),
      );
    });

    test('fails when a baseline entry is no longer violated', () {
      expect(() => run(['known-a']), throwsA(isA<TestFailure>()));
    });

    test('a rule with no baseline file must be clean', () {
      expect(
        () => expectNoNewViolations(
          'unlisted',
          ['something'],
          reason: 'test rule',
          storeDir: store,
        ),
        throwsA(isA<TestFailure>()),
      );
      expect(
        () => expectNoNewViolations(
          'unlisted',
          [],
          reason: 'test rule',
          storeDir: store,
        ),
        returnsNormally,
      );
    });
  });
}
