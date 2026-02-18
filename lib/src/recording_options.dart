/// Bitrate control mode for platform video encoders.
enum RecorderBitrateMode {
  cbr,
  vbr,
}

/// Recommended defaults used when encoder params are not supplied.
abstract final class RecorderEncodingDefaults {
  static const int encoderFps = 30;
  @Deprecated('Use encoderFps instead.')
  static const int targetFps = encoderFps;
  static const int bitrateBps = 2000000;
  static const int iFrameIntervalSec = 1;
  static const RecorderBitrateMode bitrateMode = RecorderBitrateMode.cbr;
}
