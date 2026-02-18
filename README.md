# Flutter Widget Recorder

A Flutter plugin for recording widget content as video (H.264/MP4) or image sequences on iOS and Android.

## Features

- Record any Flutter widget as a video (MP4, H.264 codec)
- Frame-accurate capture with custom resolution and pixel ratio
- Handles devicePixelRatio and pixel alignment for video codecs
- Automatic padding to meet video codec requirements (multiples of 16)
- Error diagnostics and robust handling of edge cases
- Cross-platform support (iOS and Android)

## Limitations

- The plugin can only record Flutter-rendered widgets

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_widget_recorder: ^0.1.0
```

Then run:

```bash
flutter pub get
```

## Usage

First, create a controller in your StatefulWidget:

```dart
class _MyWidgetState extends State<MyWidget> {
  final WidgetRecorderController _controller = WidgetRecorderController(
    targetFps: 30, // Optional: Set target FPS
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  // ... rest of your widget code
}
```

Wrap the widget you want to record:

```dart
Widget build(BuildContext context) {
  return WidgetRecorderWrapper(
    controller: _controller,
    child: YourWidget(),
  );
}
```

Start and stop recording:

```dart
// Start recording
await _controller.startRecording(
  'my_video',
  pixelRatio: MediaQuery.devicePixelRatioOf(context),
);

// Stop recording
await _controller.stopRecording();

// Get the path to the recorded video
final videoPath = _controller.path;
```

Optional encoder tuning params are also supported:

```dart
await _controller.startRecording(
  'my_video',
  pixelRatio: MediaQuery.devicePixelRatioOf(context),
  targetFps: 60,
  bitrateBps: 6_000_000,
  iFrameIntervalSec: 1,
  bitrateMode: RecorderBitrateMode.vbr,
);
```

Defaults used by the plugin when params are omitted:

- `targetFps`: `30`
- `bitrateBps`: `2_000_000`
- `iFrameIntervalSec`: `1`
- `bitrateMode`: `RecorderBitrateMode.cbr`

Migration note: existing API usage remains valid. If you do not pass these optional fields, behavior stays backward-compatible.

## Example

Check out the [example](example/lib/main.dart) for a complete implementation that includes:

- Recording a widget with animation
- Start/Stop recording controls
- Sharing the recorded video
- Display of the recording path

## Platform Notes

### iOS

- **Pixel Alignment:** iOS H.264 video requires frame sizes to be multiples of 16. The plugin automatically pads frames as needed. Extra space is filled with black pixels.
- **Automatic Adjustment:** The widget automatically adjusts (pads) the recorded area to the nearest multiple of 16 pixels to ensure compatibility with the video codec. You do not need to manually align your widget size.
- **Padding:** If your widget size is not a multiple of 16, the output video will have paddings on the right and/or bottom.
- **Encoder Params:** `targetFps`, `bitrateBps`, and `iFrameIntervalSec` are mapped to AVAssetWriter compression settings. `bitrateMode` is accepted for API parity but ignored on iOS (safe no-op).

### Android

- **Pixel Alignment:** Similar to iOS, Android H.264 video requires frame sizes to be multiples of 16. The plugin handles this automatically.
- **Tunable Encoding:** Android encoder settings are configurable via `startRecording(...)`.
- **Recommended Android Ranges:**
  - `targetFps`: 24-60
  - `bitrateBps`: 2_000_000-10_000_000 (increase for high resolution content)
  - `iFrameIntervalSec`: 1-2
  - `bitrateMode`: `RecorderBitrateMode.cbr` for stability, `RecorderBitrateMode.vbr` for better quality/size tradeoff

### Performance

- Recording at high resolutions or high frame rates may impact performance on both platforms.
- Consider using lower resolutions or frame rates for better performance.

## Troubleshooting

- If you see errors about frame size or stride, ensure you are passing the correct width, height, and pixelRatio.
- If you see black borders, this is due to codec alignment requirements (see above).
- If Android encoding fails with aggressive settings, the plugin retries with safe defaults (`cbr`, `30fps`, `2_000_000bps`, `1s` keyframe interval).
- For high resolution + high fps recordings, start with moderate settings and scale gradually:
  - 1080p @ 30fps: try `4_000_000` to `8_000_000` bitrate
  - 1080p @ 60fps: try `8_000_000` to `16_000_000` bitrate
  - If frames drop or encoding errors occur, reduce `targetFps` and/or `bitrateBps`
- For more details, see the [CHANGELOG.md](CHANGELOG.md).

## License

MIT
