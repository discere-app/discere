import 'package:discere/app/bootstrap/inat_provenance_step.dart';
import 'package:discere/app/bootstrap/reference_id_alias_step.dart';
import 'package:discere/app/bootstrap/species_image_storage_step.dart';

/// Brings the user data in line with the installed reference database, on
/// every start before any service is built: first its IDs, then the iNat
/// data, which is held against the reference database by those IDs, then
/// the species image storage, which keeps the images of the species still
/// needed and of the iNat photos that remain.
Future<void> alignUserDataWithReferenceDb() async {
  await applyReferenceIdAliases();
  await reconcileINatProvenance();
  await sweepSpeciesImageStorage();
}
