/// Architecture test – SafeArea usage in standalone pages.
///
/// All *_page.dart files that render a Scaffold without a
/// BottomNavigationBar must use the SafeArea widget (not just useSafeArea:)
/// to prevent content from being obscured by the Android system navigation
/// bar in edge-to-edge mode (enforced on Android 15+).
///
/// The established pattern in this codebase is:
///
///   body: SafeArea(
///     child: ...,
///   ),
///
/// Also checked: SearchSpeciesDelegate, which renders scrollable content
/// inside a SearchDelegate scaffold without being a *_page.dart file.
///
/// Run with: flutter test test/architecture/safe_area_convention_test.dart
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'arch_assertions.dart';

void main() {
  group('Architecture – SafeArea convention', () {
    test(
      'page files with Scaffold and no BottomNavigationBar must use SafeArea',
      () {
        // These pages only show non-scrolling, centered loading/error widgets
        // (CircularProgressIndicator, error text). Content never reaches the
        // screen edges, so SafeArea is not required.
        const allowedWithoutSafeArea = <String>{
          'lib/app/species_detail_loader_page.dart',
        };

        final violations = <String>[];
        final libDir = Directory('lib');
        var scannedPages = 0;
        var scaffoldPages = 0;

        for (final entity in libDir.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('_page.dart')) continue;

          final path = entity.path.replaceAll('\\', '/');
          if (allowedWithoutSafeArea.any((e) => path.endsWith(e))) continue;

          final src = entity.readAsStringSync();
          scannedPages++;

          // Only check files that actually build a Scaffold.
          if (!src.contains('Scaffold(')) continue;
          scaffoldPages++;

          // A Scaffold with BottomNavigationBar automatically places the body
          // above the system navigation bar — no explicit SafeArea needed.
          if (src.contains('bottomNavigationBar:')) continue;

          // Must use SafeArea( as a widget, not just useSafeArea: (a parameter
          // on showModalBottomSheet that is unrelated to the page body).
          if (!src.contains('SafeArea(')) {
            violations.add(path);
          }
        }

        expectScanFound(scannedPages, 10, '*_page.dart files');
        expectScanFound(scaffoldPages, 8, 'pages building a Scaffold');

        expect(
          violations,
          isEmpty,
          reason:
              'ARCH-05: these pages have a Scaffold without '
              'BottomNavigationBar '
              'but no SafeArea widget. Wrap the body:\n\n'
              '  body: SafeArea(\n'
              '    child: ...,\n'
              '  ),\n\n'
              'Violations:\n  ${violations.join('\n  ')}',
        );
      },
    );

    test('SearchSpeciesDelegate result content uses SafeArea', () {
      final src = File(
        'lib/catalog/search/search_species_delegate.dart',
      ).readAsStringSync();

      expect(
        src,
        contains('SafeArea('),
        reason:
            'SearchSpeciesDelegate renders scrollable results inside a '
            'SearchDelegate scaffold. Wrap the output of buildResults / '
            'buildSuggestions with SafeArea to prevent content from being '
            'obscured by the Android navigation bar.',
      );
    });
  });
}
