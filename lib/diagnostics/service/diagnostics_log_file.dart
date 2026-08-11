import 'dart:io';

import 'package:discere/shared/util/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Rotating on-disk debug log. Writes are serialized through an internal
/// queue since [appendLine] is called fire-and-forget from [Logger]'s
/// persistence sink and must never interleave two writes to the same file.
class DiagnosticsLogFile {
  static final _log = Logger.forType(DiagnosticsLogFile);

  static const fileName = 'discere_debug_log.txt';

  /// Once the file exceeds this size, it's trimmed back down to
  /// [_trimToBytes] (dropping the oldest lines) on the next write.
  static const _maxBytes = 1024 * 1024;
  static const _trimToBytes = 512 * 1024;

  Future<void> _writeQueue = Future<void>.value();

  Future<File> file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, fileName));
  }

  Future<void> appendLine(String line) {
    _writeQueue = _writeQueue.then((_) => _appendLine(line)).catchError((
      Object error,
    ) {
      _log.warn('write failed: $error');
    });
    return _writeQueue;
  }

  Future<void> _appendLine(String line) async {
    final target = await file();
    await target.writeAsString('$line\n', mode: FileMode.append, flush: false);
    if (await target.length() > _maxBytes) {
      await _trim(target);
    }
  }

  Future<void> _trim(File target) async {
    final content = await target.readAsString();
    final trimmed = content.length > _trimToBytes
        ? content.substring(content.length - _trimToBytes)
        : content;
    final newlineIndex = trimmed.indexOf('\n');
    final withoutPartialLine = newlineIndex >= 0
        ? trimmed.substring(newlineIndex + 1)
        : trimmed;
    await target.writeAsString(withoutPartialLine, mode: FileMode.write);
  }

  Future<String> readAll() async {
    final target = await file();
    if (!await target.exists()) return '';
    return target.readAsString();
  }

  Future<void> clear() async {
    final target = await file();
    if (await target.exists()) {
      await target.writeAsString('', mode: FileMode.write);
    }
  }
}
