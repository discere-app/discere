String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

/// Rounds up to the nearest 10 MB, e.g. "90 MB" for 81.2 MB — for
/// user-facing "about this much data" download-size copy, where the actual
/// transfer (compression, HTTP overhead) can run slightly over the
/// manifest's byte count and a precise-looking figure would then read as
/// wrong. Always rounds up so the shown estimate is never an understatement.
String formatApproxSizeMB(int bytes) {
  final roundedMb = (bytes / (1024 * 1024) / 10).ceil() * 10;
  return '$roundedMb MB';
}
