import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_widget_recorder_platform_interface.dart';
import 'recording_options.dart';

/// An implementation of [FlutterWidgetRecorderPlatform] that uses method channels.
class MethodChannelFlutterWidgetRecorder extends FlutterWidgetRecorderPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_widget_recorder');

  @override
  Future<bool> startRecording({
    required String name,
    required int width,
    required int height,
    required double pixelRatio,
    int? encoderFps,
    int? bitrateBps,
    int? iFrameIntervalSec,
    RecorderBitrateMode? bitrateMode,
  }) async {
    const String methodName = 'startRecording';
    final Map<String, dynamic> args = {
      'name': name,
      'width': width,
      'height': height,
      'pixelRatio': pixelRatio,
      if (encoderFps != null) 'targetFps': encoderFps,
      if (bitrateBps != null) 'bitrateBps': bitrateBps,
      if (iFrameIntervalSec != null) 'iFrameIntervalSec': iFrameIntervalSec,
      if (bitrateMode != null) 'bitrateMode': bitrateMode.name,
    };

    final bool? result =
        await methodChannel.invokeMethod<bool>(methodName, args);
    return result ?? false;
  }

  @override
  Future<void> pushFrame({
    required Uint8List frame,
    required int width,
    required int height,
    required int timestamp,
  }) async {
    const String methodName = 'pushFrame';
    final Map<String, dynamic> args = {
      'pixels': frame,
      'width': width,
      'height': height,
      'timestampMs': timestamp,
    };
    await methodChannel.invokeMethod<void>(methodName, args);
  }

  @override
  Future<String?> stopRecording() async {
    const String methodName = 'stopRecording';
    final String? result = await methodChannel.invokeMethod<String>(methodName);
    return result;
  }
}
