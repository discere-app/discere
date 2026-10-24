import 'package:discere/app/bootstrap/inat_provenance_step.dart';
import 'package:discere/app/bootstrap/reference_id_alias_step.dart';

/// Brings the user data in line with the installed reference database, on
/// every start before any service is built: first its IDs, then the iNat
/// data, which is held against the reference database by those IDs.
Future<void> alignUserDataWithReferenceDb() async {
  await applyReferenceIdAliases();
  await reconcileINatProvenance();
}
