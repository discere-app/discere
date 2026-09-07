/// Architecture tests — layer direction inside a slice.
///
/// `module_dependency_test.dart` guards the seven top-level slice
/// boundaries. Inside a slice every direction was allowed, and that is where
/// the coupling this suite exists to prevent actually grew: a model reaching
/// into a repository, a repository reaching up into presentation.
///
/// The rules below are the ones the codebase already satisfies, so they are
/// asserted outright rather than ratcheted.
///
/// Note that `**/service/**` importing `**/presentation/**` is deliberately
/// NOT forbidden: presenters here are pure derived-state functions, and the
/// enrichment queue service composes display state before handing it to
/// widgets.
///
/// Run with: flutter test test/architecture/layer_boundary_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'arch_assertions.dart';
import 'import_graph.dart';

/// `from` may not import `to`, except where `except` says otherwise.
/// Ordered outermost-first for readability.
const _rules = <({String from, String to, String why, List<String> except})>[
  (
    from: '**',
    to: '**/repository/**',
    except: ['**/repository/**', '**/service/**', 'app/wiring/**',
        'app/bootstrap/**'],
    why: 'Only the service layer talks to persistence. A widget holding a '
        'repository cannot be built in a test without a real database, and '
        'it puts SQL access one import away from any screen. Add a method '
        'to the slice\'s service instead, or read the model from a file '
        'that declares it rather than from the repository that returns it.\n'
        'app/wiring/ and app/bootstrap/ are exempt: building collaborators '
        'is what the composition root is for (same exemption as ARCH-09).',
  ),
  (
    from: '**/model/**',
    to: '**/repository/**',
    except: [],
    why: 'A model that reaches for a repository inverts the layer it sits '
        'in, and tends to do so only to borrow a type the repository '
        're-exports. Import the file that declares the type instead.',
  ),
  (
    from: '**/model/**',
    to: '**/service/**',
    except: [],
    why: 'A model describes data; it does not orchestrate. Move the logic '
        'that wants the service into the service, or into a presenter.',
  ),
  (
    from: '**/model/**',
    to: '**/presentation/**',
    except: [],
    why: 'A model must not know how it is displayed.',
  ),
  (
    from: '**/repository/**',
    to: '**/service/**',
    except: [],
    why: 'Persistence sits below business logic. If a repository needs a '
        'decision from a service, the caller should be making it.',
  ),
  (
    from: '**/repository/**',
    to: '**/presentation/**',
    except: [],
    why: 'Persistence must not know how its rows are displayed.',
  ),
  (
    from: 'enrichment/pipeline/**',
    to: 'enrichment/queue/**',
    except: [],
    why: 'The queue orchestrates the pipeline, not the other way round. What '
        'both need — the capability and work-state vocabulary, the deck '
        'projection, the failure classifier — lives at slice level in '
        'enrichment/model/ and enrichment/service/.',
  ),
];

void main() {
  final graph = buildImportGraph();

  group('Architecture – the scan itself', () {
    test('sees the source tree', () {
      expectScanFound(graph.length, 200, 'Dart files under lib/');
      expectScanFound(edgeCount(graph), 700, 'in-project import/export edges');
    });

    test('every layer pattern still matches files', () {
      for (final pattern in {
        for (final rule in _rules) ...[rule.from, rule.to],
      }) {
        expectScanFound(
          filesMatching(graph, pattern).length,
          1,
          'files matching "$pattern"',
        );
      }
    });
  });

  group('Architecture – layer direction', () {
    for (final rule in _rules) {
      test('${rule.from} does not import ${rule.to}', () {
        final violations = forbiddenImports(
          graph,
          from: rule.from,
          to: rule.to,
          except: rule.except,
        );
        expect(
          violations,
          isEmpty,
          reason:
              'ARCH-11: ${rule.why}\n'
              'Violations:\n  ${violations.join('\n  ')}',
        );
      });
    }
  });
}
