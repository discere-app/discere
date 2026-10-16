/// The reference-database manifest: every release it offers, at most one per
/// schema version.
///
/// The manifest names one release per schema under `schemas` — the newest
/// release of that schema, keyed by the schema version — and repeats the
/// newest schema-1 release at its top level for app builds that predate
/// `schemas`. Without `schemas` the top level is the only release.
///
/// Fields this class does not know (`publishedAt`, anything added later) are
/// ignored, so the format can grow without breaking app builds already out.
class ReferenceDbManifest {
  final List<ReferenceDbRelease> releases;

  const ReferenceDbManifest(this.releases);

  /// Throws [FormatException] for a `schemas` key that is not an integer and
  /// for a release missing a required field or carrying one of the wrong
  /// type.
  factory ReferenceDbManifest.fromJson(Map<String, dynamic> json) {
    final schemas = json['schemas'];
    if (schemas == null) {
      return ReferenceDbManifest([
        ReferenceDbRelease._fromJson(
          json,
          schemaVersion: _required<int>(json, 'schemaVersion'),
        ),
      ]);
    }
    if (schemas is! Map<String, dynamic>) {
      throw const FormatException('"schemas" is not an object');
    }
    return ReferenceDbManifest([
      for (final MapEntry(:key, :value) in schemas.entries)
        if (value is Map<String, dynamic>)
          ReferenceDbRelease._fromJson(value, schemaVersion: _schemaKey(key))
        else
          throw FormatException('"schemas"."$key" is not an object'),
    ]);
  }

  /// The schema versions the manifest offers a release for.
  Set<int> get schemaVersions => {
    for (final release in releases) release.schemaVersion,
  };

  /// The newest release an app reading [supportedSchemaVersions] can
  /// install, or null when none of them is offered.
  ///
  /// Newest by [ReferenceDbRelease.version], a counter running across all
  /// schemas: a schema-1 release published after a schema-2 one is the
  /// newer, and the higher schema alone would pass it over. Should two
  /// releases share a version, the higher schema wins.
  ReferenceDbRelease? newestReadable(Set<int> supportedSchemaVersions) {
    ReferenceDbRelease? newest;
    for (final release in releases) {
      if (!supportedSchemaVersions.contains(release.schemaVersion)) continue;
      if (newest == null ||
          release.version > newest.version ||
          (release.version == newest.version &&
              release.schemaVersion > newest.schemaVersion)) {
        newest = release;
      }
    }
    return newest;
  }

  static int _schemaKey(String key) =>
      int.tryParse(key) ??
      (throw FormatException('"schemas" key "$key" is not an integer'));
}

/// One published reference database: what to download, how to verify it,
/// and what it is.
class ReferenceDbRelease {
  /// Counts releases across all schemas; the app installs a release only
  /// when its version is above the installed one.
  final int version;
  final int schemaVersion;
  final String url;
  final String sha256;

  /// 0 when the manifest does not say.
  final int compressedSizeBytes;

  const ReferenceDbRelease({
    required this.version,
    required this.schemaVersion,
    required this.url,
    required this.sha256,
    required this.compressedSizeBytes,
  });

  // The schema version is passed in: an entry under `schemas` takes it from
  // its key, the top level from its own field.
  factory ReferenceDbRelease._fromJson(
    Map<String, dynamic> json, {
    required int schemaVersion,
  }) => ReferenceDbRelease(
    version: _required<int>(json, 'version'),
    schemaVersion: schemaVersion,
    url: _required<String>(json, 'url'),
    sha256: _required<String>(json, 'sha256'),
    compressedSizeBytes: switch (json['compressedSizeBytes']) {
      null => 0,
      final int size => size,
      final other => throw FormatException(
        '"compressedSizeBytes" is not an integer: $other',
      ),
    },
  );
}

T _required<T>(Map<String, dynamic> json, String key) => switch (json[key]) {
  final T value => value,
  null => throw FormatException('Release without "$key"'),
  final other => throw FormatException('"$key" has the wrong type: $other'),
};
