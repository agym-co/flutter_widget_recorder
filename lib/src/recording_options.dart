/// Bitrate control mode for platform video encoders.
enum RecorderBitrateMode {
  cbr,
  vbr,
}

/// Recommended defaults used when encoder params are not supplied.
abstract final class RecorderEncodingDefaults {
  static const int targetFps = 30;
  static const int bitrateBps = 2000000;
  static const int iFrameIntervalSec = 1;
  static const RecorderBitrateMode bitrateMode = RecorderBitrateMode.cbr;
}
