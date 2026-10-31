import 'package:discere/shared/util/constants.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

/// Headers for an image a widget loads itself — `Image.network`,
/// `NetworkImage`, `CachedNetworkImage`. Those go out through the
/// platform's HTTP client rather than the app's own, so they carry the
/// app's User-Agent only when it is handed to them: image hosts block by
/// User-Agent, and a picture the app shows has to be asked for as the app.
extension ImageRequestHeadersExtension on BuildContext {
  Map<String, String> get imageRequestHeaders => {
    'User-Agent': AppConstants.userAgentFor(read<PackageInfo>().version),
  };
}
