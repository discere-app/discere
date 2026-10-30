import 'dart:io';

/// Keeps integration tests offline: every connection a `dart:io`
/// [HttpClient] would open is refused before a socket exists, for every
/// address including loopback.
///
/// All of the app's HTTP goes through such a client — `http.Client()` is an
/// `IOClient` on this platform, and `NetworkImage` and `CachedNetworkImage`
/// build on one too — so a test that wants an answer injects its own client
/// or downloader (see `startApp`) instead of reaching a real server.
///
/// Refused rather than timed out, because a timeout only holds back a
/// connection that is slower than it: a fast network would still let the
/// request through and hand the test whatever the live server answers, such
/// as a manifest that offers a reference-DB update.
class OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionFactory = (url, proxyHost, proxyPort) => Future.error(
        SocketException(
          'Integration tests run offline; refused connection to ${url.host}',
        ),
      );
  }
}
