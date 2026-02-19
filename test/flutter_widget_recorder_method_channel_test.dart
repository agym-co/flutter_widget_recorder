import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_recorder/src/flutter_widget_recorder_method_channel.dart';
import 'package:flutter_widget_recorder/src/recording_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelFlutterWidgetRecorder platform =
      MethodChannelFlutterWidgetRecorder();
  const MethodChannel channel = MethodChannel('flutter_widget_recorder');
  MethodCall? lastCall;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        lastCall = methodCall;
        switch (methodCall.method) {
          case 'startRecording':
            return true;
          case 'stopRecording':
            return 'hello';
          case 'pushFrame':
            return null;
          default:
            throw PlatformException(
              code: 'unimplemented',
              message: '${methodCall.method} not implemented',
            );
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('startRecording without optional params omits them from payload',
      () async {
    expect(
      await platform.startRecording(
        name: 'test',
        width: 100,
        height: 100,
        pixelRatio: 1.0,
      ),
      true,
    );
    expect(lastCall?.arguments, {
      'name': 'test',
      'width': 100,
      'height': 100,
      'pixelRatio': 1.0,
    });
  });

  test('startRecording forwards optional encoder args', () async {
    await platform.startRecording(
      name: 'test',
      width: 100,
      height: 100,
      pixelRatio: 1.0,
      encoderFps: 60,
      bitrateBps: 4000000,
      iFrameIntervalSec: 2,
      bitrateMode: RecorderBitrateMode.vbr,
    );

    expect(lastCall?.arguments, {
      'name': 'test',
      'width': 100,
      'height': 100,
      'pixelRatio': 1.0,
      'targetFps': 60,
      'bitrateBps': 4000000,
      'iFrameIntervalSec': 2,
      'bitrateMode': 'vbr',
    });
  });

  test('stopRecording', () async {
    expect(await platform.stopRecording(), 'hello');
  });

  test('pushFrame', () async {
    await platform.pushFrame(
      frame: Uint8List(0),
      width: 100,
      height: 100,
      timestamp: 0,
    );
  });
}
