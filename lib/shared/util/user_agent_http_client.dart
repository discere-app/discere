import 'package:http/http.dart' as http;

/// Sends every request under the User-Agent it is given, so no client built
/// on top of it has to know the header exists.
///
/// Overwrites a `User-Agent` a caller set rather than keeping it: the app
/// has a single identity, and a caller's own copy of it is exactly what goes
/// stale when the version moves on.
class UserAgentHttpClient extends http.BaseClient {
  final http.Client _inner;
  final String _userAgent;

  UserAgentHttpClient(this._inner, this._userAgent);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['User-Agent'] = _userAgent;
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
  }
}
