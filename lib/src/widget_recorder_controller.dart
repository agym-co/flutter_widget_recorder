import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'flutter_widget_recorder.dart';
import 'recording_options.dart';

/// Controller for recording widget
class WidgetRecorderController with ChangeNotifier {
  final FlutterWidgetRecorder _recorder;
  final Duration _frameInterval;
  final int _captureFps;
  final bool isWithTicker;

  WidgetRecorderController({
    required int captureFps,
    this.isWithTicker = false,
  })  : _captureFps = captureFps,
        _frameInterval = Duration(milliseconds: (1000 / captureFps).floor()),
        _recorder = FlutterWidgetRecorder();

  /// Global key to the widget to be recorded.
  final GlobalKey repaintKey = GlobalKey();

  /// Whether the recording is in progress.
  bool _isRecording = false;

  /// Interval between frames.
  Duration get frameInterval => _frameInterval;

  /// Timer for recording.
  Timer? _timer;

  /// Ticker for recording. Sometimes it's more accurate than timer.
  Ticker? _ticker;

  /// Prevents overlapping frame captures when the pipeline can't keep up.
  bool _isCapturingFrame = false;

  /// Path to the recorded video.
  String? _path;

  /// Whether the recording is in progress.
  bool get isRecording => _isRecording;

  /// Path to the recorded video.
  String? get path => _path;

  /// Start recording.
  /// Pass devicePixelRatio explicitly here.
  Future<void> startRecording(
    String name, {
    required double pixelRatio,
    int? encoderFps,
    int? bitrateBps,
    int? iFrameIntervalSec,
    RecorderBitrateMode? bitrateMode,
  }) async {
    if (_isRecording) return;
    final ctx = repaintKey.currentContext;
    if (ctx == null) return;
    final size = ctx.size;
    if (size == null) return;

    final ok = await _recorder.startRecording(
      name: name,
      width: size.width.toInt(),
      height: size.height.toInt(),
      pixelRatio: pixelRatio,
      encoderFps: encoderFps ?? _captureFps,
      bitrateBps: bitrateBps,
      iFrameIntervalSec: iFrameIntervalSec,
      bitrateMode: bitrateMode,
    );
    if (ok) {
      _isRecording = true;
      if (isWithTicker) {
        _ticker = Ticker(
          (_) => _captureFrame(pixelRatio),
        );
        _ticker?.start();
      } else {
        _timer = Timer.periodic(
          _frameInterval,
          (_) => _captureFrame(pixelRatio),
        );
      }
      notifyListeners();
    }
  }

  /// Stop recording.
  Future<void> stopRecording() async {
    if (!_isRecording) return;
    _timer?.cancel();
    _ticker?.stop();
    _isRecording = false;
    _isCapturingFrame = false;
    _path = await _recorder.stopRecording();
    notifyListeners();
  }

  /// Capture frame and send to native. Skips if the previous capture is still
  /// in flight to prevent pipeline backup.
  Future<void> _captureFrame(double pixelRatio) async {
    if (_isCapturingFrame) return;
    _isCapturingFrame = true;
    try {
      final boundary = repaintKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final imageWidth = image.width;
      final imageHeight = image.height;
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (byteData == null) return;

      final pixels = byteData.buffer.asUint8List();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      await _recorder.pushFrame(
        frame: pixels,
        width: imageWidth,
        height: imageHeight,
        timestamp: timestamp,
      );
    } catch (e) {
      debugPrint('Error capturing frame: $e');
    } finally {
      _isCapturingFrame = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ticker?.dispose();
    if (_isRecording) stopRecording();
    super.dispose();
  }
}
