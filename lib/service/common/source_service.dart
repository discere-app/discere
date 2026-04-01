import 'package:discere/model/source.dart';
import 'package:discere/persistence/source_repository.dart';

class SourceService {
  final SourcesRepository _sourcesRepository;

  SourceService(this._sourcesRepository);

  Future<List<Source>> getAllSources() async {
    final sources = await _sourcesRepository.findAll();
    
    // Add iNaturalist as a synthetic source since it's a runtime integration
    sources.add(const Source(
      id: 'inaturalist',
      name: 'iNaturalist',
      category: 'Community Photos',
      citation: 'iNaturalist. (2026). iNaturalist Research-grade Observations. '
                'Occurrences retrieved from https://www.inaturalist.org. '
                'Photos curated by the community and licensed under CC BY, CC-BY-SA, CC-BY-NC, or CC0.',
      url: 'https://www.inaturalist.org',
      faviconUrl: 'https://www.inaturalist.org/favicon.ico',
      licenseKey: 'CC BY / CC0',
      licenseUrl: 'https://www.inaturalist.org/pages/help#licenses',
      displayOrder: 30, // Show after FishBase/SeaLifeBase
    ));
    
    return sources;
  }

  Future<List<({String key, String? licenseUrl})>> getDistinctLicenses() async {
    final licenses = await _sourcesRepository.distinctLicenses();
    
    // Add CC-BY for iNaturalist if not already there
    if (!licenses.any((l) => l.key == 'CC BY / CC0')) {
      licenses.add((
        key: 'CC BY / CC0',
        licenseUrl: 'https://www.inaturalist.org/pages/help#licenses'
      ));
    }
    
    return licenses;
  }
}
