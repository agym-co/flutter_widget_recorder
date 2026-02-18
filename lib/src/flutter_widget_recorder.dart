import 'dart:typed_data';

import 'flutter_widget_recorder_platform_interface.dart';
import 'recording_options.dart';

class FlutterWidgetRecorder {
  Future<bool> startRecording({
    required String name,
    required int width,
    required int height,
    required double pixelRatio,
    int? encoderFps,
    @Deprecated('Use encoderFps instead.') int? targetFps,
    int? bitrateBps,
    int? iFrameIntervalSec,
    RecorderBitrateMode? bitrateMode,
  }) {
    final int? effectiveEncoderFps = encoderFps ?? targetFps;
    return FlutterWidgetRecorderPlatform.instance.startRecording(
      name: name,
      width: width,
      height: height,
      pixelRatio: pixelRatio,
      encoderFps: effectiveEncoderFps,
      bitrateBps: bitrateBps,
      iFrameIntervalSec: iFrameIntervalSec,
      bitrateMode: bitrateMode,
    );
  }

  Future<void> pushFrame({
    required Uint8List frame,
    required int width,
    required int height,
    required int timestamp,
  }) {
    return FlutterWidgetRecorderPlatform.instance.pushFrame(
      frame: frame,
      width: width,
      height: height,
      timestamp: timestamp,
    );
  }

  Future<String?> stopRecording() {
    return FlutterWidgetRecorderPlatform.instance.stopRecording();
  }
}
