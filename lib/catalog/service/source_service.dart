import 'package:discere/catalog/model/source.dart';
import 'package:discere/catalog/repository/source_repository.dart';

class SourceService {
  /// What the reference DB's own `inaturalist` source says. Reference DBs
  /// built before the ETL had that source don't list it, so the page adds
  /// this entry for them and looks the same either way.
  static const _iNaturalistSource = Source(
    id: 'inaturalist',
    name: 'iNaturalist',
    category: 'Community Photos',
    citation:
        'iNaturalist. (2026). iNaturalist Research-grade Observations. '
        'Occurrences retrieved from https://www.inaturalist.org. '
        'Photos curated by the community and licensed under CC BY, CC-BY-SA, CC-BY-NC, or CC0.',
    url: 'https://www.inaturalist.org',
    speciesUrlTemplate: 'https://www.inaturalist.org/taxa/{external_id}',
    faviconUrl: 'https://www.inaturalist.org/favicon.ico',
    licenseKey: 'CC BY / CC0',
    licenseUrl: 'https://www.inaturalist.org/pages/help#licenses',
    displayOrder: 30, // Show after FishBase/SeaLifeBase
  );

  final SourceRepository _sourcesRepository;

  SourceService(this._sourcesRepository);

  Future<List<Source>> getAllSources() async {
    final sources = await _sourcesRepository.findAll();

    if (!sources.any((source) => source.id == _iNaturalistSource.id)) {
      sources.add(_iNaturalistSource);
    }

    // Add Wikipedia as a synthetic source: a runtime integration with no
    // reference-DB counterpart.
    sources.add(
      const Source(
        id: 'wikipedia',
        name: 'Wikipedia',
        category: 'Encyclopedia',
        citation:
            'Wikipedia contributors. Article summaries retrieved from '
            'https://www.wikipedia.org. Text licensed under CC BY-SA 4.0.',
        url: 'https://www.wikipedia.org',
        faviconUrl: 'https://www.wikipedia.org/favicon.ico',
        licenseKey: 'CC BY-SA 4.0',
        licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
        displayOrder: 40, // Show after iNaturalist
      ),
    );

    return sources;
  }

  Future<List<({String key, String? licenseUrl})>> getDistinctLicenses() async {
    final licenses = await _sourcesRepository.distinctLicenses();

    // Add CC-BY for iNaturalist if not already there
    if (!licenses.any((l) => l.key == 'CC BY / CC0')) {
      licenses.add((
        key: 'CC BY / CC0',
        licenseUrl: 'https://www.inaturalist.org/pages/help#licenses',
      ));
    }

    // Add CC BY-SA for Wikipedia if not already there
    if (!licenses.any((l) => l.key == 'CC BY-SA 4.0')) {
      licenses.add((
        key: 'CC BY-SA 4.0',
        licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
      ));
    }

    return licenses;
  }
}
