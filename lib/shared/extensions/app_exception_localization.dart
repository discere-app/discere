import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/app_exception.dart';

/// Maps a caught error to a localized, user-facing description.
///
/// [AppException.message] (and any other exception's `toString()`) is
/// English-only and meant for logs/diagnostics — never interpolate it into
/// UI text. Use this instead: it looks only at the exception's *type* to
/// pick one of a small set of localized, parameter-free strings.
extension AppExceptionLocalization on AppLocalizations {
  String describeError(Object? error) {
    if (error is NetworkException) return errorNetwork;
    if (error is ServerException) return errorServer;
    return errorGeneric;
  }
}
