import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_recorder/src/flutter_widget_recorder.dart';
import 'package:flutter_widget_recorder/src/flutter_widget_recorder_method_channel.dart';
import 'package:flutter_widget_recorder/src/flutter_widget_recorder_platform_interface.dart';
import 'package:flutter_widget_recorder/src/recording_options.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterWidgetRecorderPlatform
    with MockPlatformInterfaceMixin
    implements FlutterWidgetRecorderPlatform {
  @override
  Future<void> pushFrame(
      {required Uint8List frame,
      required int width,
      required int height,
      required int timestamp}) async {
    return;
  }

  @override
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
  }) async {
    return true;
  }

  @override
  Future<String?> stopRecording() async {
    return null;
  }
}

void main() {
  final FlutterWidgetRecorderPlatform initialPlatform =
      FlutterWidgetRecorderPlatform.instance;

  test('$MethodChannelFlutterWidgetRecorder is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterWidgetRecorder>());
  });

  test('startRecording', () async {
    FlutterWidgetRecorder flutterWidgetRecorderPlugin = FlutterWidgetRecorder();
    MockFlutterWidgetRecorderPlatform fakePlatform =
        MockFlutterWidgetRecorderPlatform();
    FlutterWidgetRecorderPlatform.instance = fakePlatform;

    expect(
      await flutterWidgetRecorderPlugin.startRecording(
        name: 'test',
        width: 100,
        height: 100,
        pixelRatio: 1.0,
      ),
      true,
    );
  });
}
