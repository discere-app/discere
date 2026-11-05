/// How the download of one image URL ended, as `ImageService` reports it.
///
/// The categories are what a caller needs to decide whether trying again
/// could help: a host that could not be reached or turned the app away says
/// nothing about the image itself, a host that answered without it does, and
/// a failure on this device is neither.
sealed class ImageDownloadOutcome {
  const ImageDownloadOutcome();
}

/// The image is on disk at [localPath] — freshly downloaded, or found in the
/// local cache without a request.
final class ImageSaved extends ImageDownloadOutcome {
  final String localPath;

  const ImageSaved(this.localPath);
}

/// The request failed because of the host named [host], not because of the
/// image: see the two subtypes.
sealed class ImageHostProblem extends ImageDownloadOutcome {
  final String host;

  const ImageHostProblem(this.host);
}

/// The host could not be reached or was struggling: a dropped connection, a
/// timeout, a 408/425/429/5xx, or a host skipped outright while it cools
/// down.
final class ImageHostUnreachable extends ImageHostProblem {
  const ImageHostUnreachable(super.host);
}

/// The host answered 403: it refuses this client, whatever it was asked for.
final class ImageHostRefused extends ImageHostProblem {
  const ImageHostRefused(super.host);
}

/// The host named [host] answered and does not have the image: a 404, 410
/// or any other 4xx besides the ones [ImageHostProblem] covers.
final class ImageNotFound extends ImageDownloadOutcome {
  final String host;
  final int statusCode;

  const ImageNotFound(this.host, this.statusCode);
}

/// Something on this device failed, such as creating the storage directory
/// or writing the file. `ImageService` logs the error itself.
final class ImageLocalFailure extends ImageDownloadOutcome {
  const ImageLocalFailure();
}
