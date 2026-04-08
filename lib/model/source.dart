import 'biology/species.dart';

class Source {
  final String id;
  final String name;
  final String category;
  final String citation;
  final String url;
  final String? speciesUrlTemplate;
  final String? faviconUrl;
  final String licenseKey;
  final String? licenseUrl;
  final String? version;
  final int displayOrder;
  final String? lastImported;

  const Source({required this.id, required this.name, required this.category, required this.citation, required this.url, this.speciesUrlTemplate, this.faviconUrl, required this.licenseKey, this.licenseUrl, this.version, required this.displayOrder, this.lastImported});

factory Source.fromMap(Map<String, dynamic> map) => Source(
id:           map['id'] as String,
name:         map['name'] as String,
category:     map['category'] as String,
citation:     map['citation'] as String,
url:          map['url'] as String,
speciesUrlTemplate: map['species_url_template'] as String?,
faviconUrl:   map['favicon_url'] as String?,
licenseKey:   map['license_key'] as String,
licenseUrl:   map['license_url'] as String?,
version:      map['version'] as String?,
displayOrder: map['display_order'] as int,
lastImported: map['last_imported'] as String?,
);

/// Favicon-URL mit Fallback auf /favicon.ico — kein externer Dienst.
String get resolvedFaviconUrl {
if (faviconUrl?.isNotEmpty == true) return faviconUrl!;
return '${Uri.parse(url).origin}/favicon.ico';
}

Uri? buildSpeciesUrl(Species species) {
  final template = speciesUrlTemplate;
  if (template == null || template.isEmpty) return null;

  final genus = species.classification.genusScientificName;
  final scientificName = species.scientificName;
  final binomial = species.getBinomialName();

  final resolved = template
      .replaceAll('{external_id}', Uri.encodeComponent(species.externalId))
      .replaceAll('{genus}', Uri.encodeComponent(genus))
      .replaceAll('{species}', Uri.encodeComponent(scientificName))
      .replaceAll('{binomial}', Uri.encodeComponent(binomial));

  return Uri.tryParse(resolved);
}
}
