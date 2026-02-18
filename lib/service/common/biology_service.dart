import '../../persistence/image_service.dart';
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

    final localImagePaths =
        await _imageService.downloadAndSaveImages(species.images.toSet());
    return SpeciesWithLocalImages(species, localImagePaths);
  }
}
