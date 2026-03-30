import 'package:discere/model/source.dart';
import 'package:discere/persistence/source_repository.dart';

class SourceService {
  final SourcesRepository _sourcesRepository;

  SourceService(this._sourcesRepository);

  Future<List<Source>> getAllSources() {
    return _sourcesRepository.findAll();
  }

  Future<List<({String key, String? licenseUrl})>> getDistinctLicenses() {
    return _sourcesRepository.distinctLicenses();
  }
}
