import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_widget_recorder_method_channel.dart';
import 'recording_options.dart';

/// The platform interface for the FlutterWidgetRecorder plugin.
///
/// This interface is used to interact with the native platform implementation
/// of the FlutterWidgetRecorder plugin.
///
/// The platform interface is implemented by the [MethodChannelFlutterWidgetRecorder]
/// class.
abstract class FlutterWidgetRecorderPlatform extends PlatformInterface {
  /// Constructs a FlutterWidgetRecorderPlatform.
  FlutterWidgetRecorderPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterWidgetRecorderPlatform _instance =
      MethodChannelFlutterWidgetRecorder();

  /// The default instance of [FlutterWidgetRecorderPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterWidgetRecorder].
  static FlutterWidgetRecorderPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterWidgetRecorderPlatform] when
  /// they register themselves.
  static set instance(FlutterWidgetRecorderPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Starts recording a widget animation.
  ///
  /// The [name] parameter is the name of the video file.
  /// The [width] and [height] parameters are the dimensions of the video.
  ///
  /// Returns true if the recording started successfully, false otherwise.
  Future<bool> startRecording({
    required String name,
    required int width,
    required int height,
    required double pixelRatio,
    int? targetFps,
    int? bitrateBps,
    int? iFrameIntervalSec,
    RecorderBitrateMode? bitrateMode,
  });

  /// Pushes a frame to the recording.
  ///
  /// The [frame] parameter is the frame to push.
  /// The [width] and [height] parameters are the dimensions of the frame.
  /// The [timestamp] parameter is the timestamp of the frame.
  ///
  Future<void> pushFrame({
    required Uint8List frame,
    required int width,
    required int height,
    required int timestamp,
  });

  /// Stops the recording.
  ///
  /// Returns the path to the recorded video.
  Future<String?> stopRecording();
}
