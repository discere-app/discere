class Picture {
  final String id;
  final String species;
  final String? picname;
  final String? picturetype;
  final String? lifestage;
  final String? author;       // Fotograf / Organisation — für Attribution
  final String? copyright;    // Rohtext aus der Quelle
  final String? url;
  final String origin;
  final String? licenseKey;   // normiert, z.B. 'CC BY-NC 4.0'
  final int isUsable;         // 1 = darf angezeigt werden

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
    id:         map['id'] as String,
    species:    map['species'] as String,
    picname:    map['picname'] as String?,
    picturetype: map['picturetype'] as String?,
    lifestage:  map['lifestage'] as String?,
    author:     map['author'] as String?,
    copyright:  map['copyright'] as String?,
    url:        map['url'] as String?,
    origin:     map['origin'] as String,
    licenseKey: map['license_key'] as String?,
    isUsable:   (map['is_usable'] as int?) ?? 0,
  );

  /// Attributionstext für die UI.
  /// Laut FishBase-Lizenz muss bei jedem Bild stehen:
  ///   "© [Fotograf], from FishBase ([Lizenz])"
  String get attributionText {
    final who   = (author?.isNotEmpty == true) ? author! : origin;
    final lic   = licenseKey?.isNotEmpty == true ? licenseKey! : 'ARR';
    return '© $who, from ${_sourceName(origin)} ($lic)';
  }

  String _sourceName(String origin) => switch (origin) {
    'fishbase'    => 'FishBase',
    'sealifebase' => 'SeaLifeBase',
    _             => origin,
  };
}
