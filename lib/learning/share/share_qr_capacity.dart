/// Whether a payload fits in a QR code at all, and whether the result would
/// still be scannable in practice.
///
/// Kept out of the widget so both questions can be answered — and tested —
/// without rendering anything.
library;

import 'package:qr/qr.dart';

/// Above this module count (~QR version 25), reliable scanning by a typical
/// phone camera at a normal viewing distance gets increasingly unlikely — on
/// a phone-sized screen, modules shrink to sub-millimeter. Confirmed
/// empirically: a 227-species deck (~145 modules, version ~32) failed to
/// scan on a real device.
const int denseQrModuleCountThreshold = 117;

bool isDenseQr(int moduleCount) => moduleCount > denseQrModuleCountThreshold;

/// The QR code that renders [data] at the smallest version that holds it, or
/// null if it does not fit any QR version at all (version 40 is the largest,
/// ~2.9KB at error-correction level low).
///
/// Error correction stays at its lowest level, which leaves the most capacity
/// for a large deck.
QrCode? encodeShareQr(String data) {
  try {
    return QrCode(
      payload: QrPayload.fromString(data),
      errorCorrectLevel: QrErrorCorrectLevel.low,
    );
  } on InputTooLongException {
    return null;
  }
}
