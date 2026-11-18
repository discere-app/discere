import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where images cached by URL live on disk: one storage directory per kind of
/// image under the app documents directory, a folder per host inside it, and
/// a file named after the URL's hash. The one place that naming rule lives —
/// whatever saves, finds or clears a cached copy goes through it, so they
/// cannot disagree about which file belongs to which URL.
class CachedImageStore {
  /// The app documents directory, resolved at most once per instance. It is
  /// fixed for the process lifetime but reached over a platform channel, and
  /// a bulk resolve asks for hundreds of paths in a row — one round trip for
  /// all of them instead of one per path. An instance field rather than a
  /// static one, so a test that swaps path_provider's implementation gets the
  /// directory that test installed.
  Future<Directory>? _documentsDirectory;

  /// The app documents directory the storage directories live in.
  Future<Directory> documentsDirectory() async {
    final pending = _documentsDirectory ??= getApplicationDocumentsDirectory();
    try {
      return await pending;
    } catch (_) {
      // Only a successful lookup is worth remembering. The app holds one
      // store, so a remembered failure would leave every image path in the
      // app unresolvable for the rest of the run; dropping it lets the next
      // caller try the channel again.
      if (_documentsDirectory == pending) _documentsDirectory = null;
      rethrow;
    }
  }

  /// Where [url]'s cached copy goes in [storageDirectory], whether or not it
  /// is there yet.
  Future<String> pathFor(
    String url, {
    required String storageDirectory,
  }) async => p.join(
    (await documentsDirectory()).path,
    storageDirectory,
    _relativePathFor(url),
  );

  /// The path of [url]'s cached copy, looked for in [storageDirectory] and
  /// then in [legacyDirectories], or null when none of them has it.
  Future<String?> existingPathFor(
    String url, {
    required String storageDirectory,
    Set<String> legacyDirectories = const {},
  }) async {
    final documents = await documentsDirectory();
    final relativePath = _relativePathFor(url);

    for (final directory in {storageDirectory, ...legacyDirectories}) {
      final path = p.join(documents.path, directory, relativePath);
      if (await File(path).exists()) {
        return path;
      }
    }

    return null;
  }

  /// A URL's cached copy relative to its storage directory: a collision-safe
  /// file name (the URL's MD5, keeping its extension) inside a per-host
  /// folder. Derived once per URL so that looking through several storage
  /// directories for the same URL doesn't parse and hash it again for each
  /// one.
  String _relativePathFor(String url) {
    final uri = Uri.parse(url);
    final urlHash = md5.convert(utf8.encode(url)).toString();
    final ext = p.extension(uri.path);
    return p.join(
      uri.host.replaceAll('.', '_'),
      '$urlHash${ext.isNotEmpty ? ext : '.jpg'}',
    );
  }
}
