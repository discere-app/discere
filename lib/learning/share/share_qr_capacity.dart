/// Whether a payload fits in a QR code at all, and whether the result would
/// still be scannable in practice.
///
/// Kept out of the widget so both questions can be answered — and tested —
/// without rendering anything.
library;

import 'package:qr_flutter/qr_flutter.dart';

/// Above this module count (~QR version 25), reliable scanning by a typical
/// phone camera at a normal viewing distance gets increasingly unlikely — on
/// a phone-sized screen, modules shrink to sub-millimeter. Confirmed
/// empirically: a 227-species deck (~145 modules, version ~32) failed to
/// scan on a real device.
const int denseQrModuleCountThreshold = 117;

bool isDenseQr(int moduleCount) => moduleCount > denseQrModuleCountThreshold;

/// The module count (grid width) of the QR code that would render [data], or
/// null if it does not actually fit any QR version at all.
///
/// `QrValidator.validate` picks a candidate version but never forces the
/// underlying bit buffer to be built, so it reports `valid` even for
/// payloads that do not fit any QR version (version 40 is the largest,
/// ~2.9KB at error-correction level L) — the real capacity check only runs
/// lazily, when QrPainter builds a QrImage from the QrCode, which is too
/// late to avoid throwing mid-build. Building that same QrImage here
/// reproduces the check ahead of time, so an oversized deck gets a warning
/// instead of an uncaught exception when its share page is opened.
int? qrModuleCount(String data) {
  final validation = QrValidator.validate(
    data: data,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.L,
  );
  final qrCode = validation.qrCode;
  if (!validation.isValid || qrCode == null) return null;
  try {
    QrImage(qrCode);
    return qrCode.moduleCount;
  } on Exception {
    return null;
  }
}
