/// Import/export graph over `lib/`, built by scanning directive text rather
/// than resolving an AST.
///
/// Every reference under `lib/` is absolute (`package:discere/…` or `dart:`)
/// — there is not a single relative import in the tree — so the target path
/// is recoverable from the directive alone. That is what lets the
/// architecture rules run without the `analyzer` package, whose major
/// versions move with the Dart SDK and would otherwise cap what this project
/// can upgrade to.
library;

import 'dart:io';

/// Maps a `lib/`-relative path to the `lib/`-relative paths it references.
typedef ImportGraph = Map<String, Set<String>>;

/// `export` counts as an edge alongside `import`: a re-export couples two
/// files exactly the way an import does, and treating it as invisible would
/// hide the `enrichment` slice's re-export chains from every rule below.
final _directive = RegExp(
  r"^\s*(?:import|export)\s+'package:discere/([^']+)'",
  multiLine: true,
);

/// Scans [root] and returns every `.dart` file in it, including generated
/// ones — a rule that wants to skip those excludes them by pattern.
ImportGraph buildImportGraph({String root = 'lib'}) {
  final graph = <String, Set<String>>{};
  for (final entity in Directory(root).listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    graph[_relativeTo(entity.path, root)] = _directive
        .allMatches(entity.readAsStringSync())
        .map((match) => match.group(1)!)
        .toSet();
  }
  return graph;
}

String _relativeTo(String path, String root) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.indexOf('$root/');
  if (index == -1) return normalized;
  return normalized.substring(index + root.length + 1);
}

/// Compiles a glob over `lib/`-relative paths. `**/` spans any number of
/// leading directories (including none), a bare `**` spans any characters,
/// and `*` stops at a path separator.
RegExp globToRegExp(String pattern) {
  final buffer = StringBuffer('^');
  var index = 0;
  while (index < pattern.length) {
    if (pattern.startsWith('**/', index)) {
      buffer.write('(?:.*/)?');
      index += 3;
    } else if (pattern.startsWith('**', index)) {
      buffer.write('.*');
      index += 2;
    } else if (pattern.startsWith('*', index)) {
      buffer.write('[^/]*');
      index += 1;
    } else {
      buffer.write(RegExp.escape(pattern[index]));
      index += 1;
    }
  }
  buffer.write(r'$');
  return RegExp(buffer.toString());
}

/// The files in [graph] whose path matches [pattern].
Set<String> filesMatching(ImportGraph graph, String pattern) {
  final regExp = globToRegExp(pattern);
  return graph.keys.where(regExp.hasMatch).toSet();
}

/// Every edge from a file matching [from] to a file matching [to], formatted
/// as `<source> -> <target>` and sorted so a baseline file stays stable.
///
/// [except] exempts source files by pattern — for a rule where a small,
/// named set of files is legitimately allowed to break it. Prefer this over
/// a baseline when the exemption is permanent and explainable; a baseline is
/// for violations that are meant to disappear.
List<String> forbiddenImports(
  ImportGraph graph, {
  required String from,
  required String to,
  Iterable<String> except = const [],
}) {
  final targets = filesMatching(graph, to);
  final exempt = <String>{
    for (final pattern in except) ...filesMatching(graph, pattern),
  };
  final violations = <String>[];
  for (final source in filesMatching(graph, from)) {
    if (exempt.contains(source)) continue;
    for (final target in graph[source]!) {
      if (targets.contains(target)) {
        violations.add('$source -> $target');
      }
    }
  }
  return violations..sort();
}

/// Import cycles that run entirely inside [within], each rendered as the
/// path that closes it.
///
/// Depth-first with memoisation: a file whose subtree is fully explored is
/// never revisited, which keeps this linear in the graph size. The trade-off
/// is that only one cycle per strongly-connected component is reported —
/// enough to fail the build and point at the component, not a complete
/// enumeration.
List<String> importCycles(ImportGraph graph, {required String within}) {
  final scope = filesMatching(graph, within);
  final cycles = <String>{};
  final finished = <String>{};
  final path = <String>[];
  final onPath = <String>{};

  void visit(String file) {
    if (finished.contains(file)) return;
    if (onPath.contains(file)) {
      final start = path.indexOf(file);
      cycles.add([...path.sublist(start), file].join(' -> '));
      return;
    }
    path.add(file);
    onPath.add(file);
    for (final target in graph[file] ?? const <String>{}) {
      if (scope.contains(target)) visit(target);
    }
    path.removeLast();
    onPath.remove(file);
    finished.add(file);
  }

  for (final file in scope) {
    visit(file);
  }
  return cycles.toList()..sort();
}

/// Total number of edges in [graph] — used by the vacuity guards to tell
/// "the scan read the files but recognised no directives" apart from a
/// genuinely clean result.
int edgeCount(ImportGraph graph) =>
    graph.values.fold(0, (sum, targets) => sum + targets.length);
