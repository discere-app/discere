import 'package:discere/catalog/model/source.dart';
import 'package:discere/catalog/repository/source_repository.dart';

class SourceService {
  final SourceRepository _sourcesRepository;

  SourceService(this._sourcesRepository);

  Future<List<Source>> getAllSources() async {
    final sources = await _sourcesRepository.findAll();

    // Add iNaturalist as a synthetic source since it's a runtime integration
    sources.add(
      const Source(
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
      ),
    );

    // Add Wikipedia as a synthetic source, same reasoning as iNaturalist above.
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
