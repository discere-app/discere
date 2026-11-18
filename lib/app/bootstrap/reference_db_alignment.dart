import 'package:discere/app/bootstrap/inat_image_pruning_step.dart';
import 'package:discere/app/bootstrap/inat_provenance_step.dart';
import 'package:discere/app/bootstrap/reference_id_alias_step.dart';

/// Brings the user data in line with the installed reference database, on
/// every start before any service is built: first its IDs, then the iNat
/// data, which is held against the reference database by those IDs, then
/// the iNat image files, which belong to the iNat photos that remain.
Future<void> alignUserDataWithReferenceDb() async {
  await applyReferenceIdAliases();
  await reconcileINatProvenance();
  await pruneOrphanedINatImages();
}
