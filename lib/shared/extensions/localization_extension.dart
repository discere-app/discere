import 'package:discere/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

extension LocalizationExtension on BuildContext {
  AppLocalizations get loc => AppLocalizations.of(this)!;
}
