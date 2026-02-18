# Changelog

## [Unreleased]

### Added

- Added optional encoder parameters to `startRecording`: `targetFps`, `bitrateBps`, `iFrameIntervalSec`, and `bitrateMode` (`cbr`/`vbr`).
- Added `RecorderBitrateMode` and documented default encoder values for backward-compatible usage.
- Added Android unit coverage for bitrate mode parsing and encoder parameter normalization.

### Changed

- Android encoder now uses method-channel values instead of hardcoded frame rate/bitrate/keyframe settings.
- Android adds clamping, capability checks for bitrate mode, and startup logging of effective encoder settings.
- Android now retries with safe defaults when requested encoder configuration fails.
- iOS now accepts the same optional encoder parameters and applies supported fields to AVAssetWriter compression settings.

## [0.1.0] - 2025-06-13

### Added

- Added Android platform support
- Implemented H.264 video recording for Android using MediaCodec and MediaMuxer
- Added proper package name for Android (com.tsitser.flutter_widget_recorder)
- Added example for creating a video from camera

### Changed

- Updated package structure to support both iOS and Android platforms
- Improved documentation with platform-specific notes

## [0.0.2] - 2025-06-09

### Added

- Comments and documentation in the Swift code for easier maintenance.
- Added `isWithTicker` parameter to `WidgetRecorderController` to use `Ticker` instead of `Timer` for recording.

## [0.0.1] - 2025-07-08

### Fixed

- Corrected pixel buffer alignment for iOS video recording: now frames are padded to sizes compatible with H.264 codec requirements (multiples of 16).
- Fixed stride handling for incoming pixel data to support non-standard row sizes from Flutter.
- Eliminated errors related to mismatched frame and buffer sizes, preventing crashes and black frames.
- Improved error diagnostics and logging for frame capture and writer failures.

### Changed

- Now uses `pixelWidth` and `pixelHeight` (aligned sizes) for all AVAssetWriter and buffer operations.
- Fills extra buffer space (right and bottom) with black pixels to match codec requirements.
- Simplified and clarified the logic for copying and converting pixel data from Flutter to native iOS buffers.

---

## [Older versions]

- See previous commit history for earlier changes.
