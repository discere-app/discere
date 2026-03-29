import 'image_service.dart';
import '../../model/biology/species.dart';
import '../../model/biology/species_with_local_images.dart';

import '../../persistence/species_repository.dart';

class BiologyService {
  final SpeciesRepository _speciesRepository;
  final ImageService _imageService;

  BiologyService(this._speciesRepository, this._imageService);

  Future<Species?> getSpeciesById(String speciesId) {
    return _speciesRepository.getSpeciesById(speciesId);
  }

  Future<SpeciesWithLocalImages?> getSpeciesWithLocalImagesById(
      String speciesId) async {
    final species = await _speciesRepository.getSpeciesById(speciesId);
    if (species == null) return null;

    final urlsToDownload = species.pictures
        .map((p) => p.url)
        .where((url) => url != null && url.isNotEmpty)
        .cast<String>()
        .toSet();
        
    final urlToLocalPath = await _imageService.downloadAndSaveImagesMap(urlsToDownload);

    final localPictures = species.pictures.map((p) {
      if (p.url != null && urlToLocalPath.containsKey(p.url)) {
        return LocalPicture(p, urlToLocalPath[p.url]!);
      }
      return null;
    }).whereType<LocalPicture>().toList();

    return SpeciesWithLocalImages(species, localPictures);
  }
}
