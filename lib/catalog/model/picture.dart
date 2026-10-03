class Picture {
  final String id;
  final String species;
  final String? picname;
  final String? picturetype;
  final String? lifestage;
  final String? author; // photographer / organization — for attribution
  final String? copyright; // raw text from the source
  final String? url;
  final String origin;
  final String? licenseKey; // normalized, e.g. 'CC BY-NC 4.0'
  final int isUsable; // 1 = may be displayed

  const Picture({
    required this.id,
    required this.species,
    this.picname,
    this.picturetype,
    this.lifestage,
    this.author,
    this.copyright,
    this.url,
    required this.origin,
    this.licenseKey,
    required this.isUsable,
  });

  factory Picture.fromMap(Map<String, dynamic> map) => Picture(
    id: map['id'] as String,
    species: map['species'] as String,
    picname: map['picname'] as String?,
    picturetype: map['picturetype'] as String?,
    lifestage: map['lifestage'] as String?,
    author: map['author'] as String?,
    copyright: map['copyright'] as String?,
    url: map['url'] as String?,
    origin: map['origin'] as String,
    licenseKey: map['license_key'] as String?,
    isUsable: (map['is_usable'] as int?) ?? 0,
  );

  /// Builds a [Picture] from an `inat_photo_cache` row — a different column
  /// shape than the FishBase/SeaLifeBase `pictures` table [fromMap] reads
  /// (no `species` column there, so [speciesId] is passed in separately).
  factory Picture.fromINatCacheRow(Map<String, dynamic> row, String speciesId) {
    final licenseCode = row['license_code'] as String? ?? '';
    return Picture(
      id: 'inat_${speciesId}_${row['photo_url'].hashCode}',
      species: speciesId,
      url: row['photo_url'] as String?,
      author: row['attribution'] as String?,
      origin: 'iNaturalist',
      licenseKey: licenseCode.toUpperCase(),
      isUsable: 1,
    );
  }

  /// Attribution text for the UI.
  String get attributionText {
    final who = (author?.isNotEmpty == true) ? author! : origin;
    final lic = licenseKey ?? 'ARR';
    return '© $who, from $origin ($lic)';
  }
}
