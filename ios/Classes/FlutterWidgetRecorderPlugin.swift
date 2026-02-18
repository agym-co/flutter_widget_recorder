// FlutterWidgetRecorderPlugin.swift
import Flutter
import UIKit
import AVFoundation
import CoreMedia
import CoreImage

public class FlutterWidgetRecorderPlugin: NSObject, FlutterPlugin {
    private struct EncoderConfig: Equatable {
        let targetFps: Int
        let bitrateBps: Int
        let iFrameIntervalSec: Int
        let bitrateMode: String

        static let `default` = EncoderConfig(
            targetFps: 30,
            bitrateBps: 2_000_000,
            iFrameIntervalSec: 1,
            bitrateMode: "cbr"
        )
    }

    // MARK: — properties
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var videoOutputURL: URL?
    private var isRecording = false
    private var pixelWidth = 0
    private var pixelHeight = 0
    // original frame dims before alignment
    private var frameWidth = 0
    private var frameHeight = 0
    private var firstTimestamp: CMTime?
    private let ciContext = CIContext()
    private var encoderConfig: EncoderConfig = .default

    // MARK: — registration
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter_widget_recorder",
            binaryMessenger: registrar.messenger()
        )
        let instance = FlutterWidgetRecorderPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // MARK: — handler
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startRecording":
            guard let args = call.arguments as? [String: Any],
                  let name       = args["name"] as? String,
                  let width      = args["width"] as? Int,
                  let height     = args["height"] as? Int,
                  let pixelRatio = args["pixelRatio"] as? Double
            else {
                return result(FlutterError(code: "INVALID_ARGS", message: "Expected name, width, height, pixelRatio", details: nil))
            }
            // compute physical dims
            let unW = Int(Double(width) * pixelRatio)
            let unH = Int(Double(height) * pixelRatio)
            frameWidth = unW; frameHeight = unH
            // align to 16
            pixelWidth  = ((unW + 15)/16)*16
            pixelHeight = ((unH + 15)/16)*16
            encoderConfig = buildEncoderConfig(
                targetFps: (args["targetFps"] as? NSNumber)?.intValue,
                bitrateBps: (args["bitrateBps"] as? NSNumber)?.intValue,
                iFrameIntervalSec: (args["iFrameIntervalSec"] as? NSNumber)?.intValue,
                bitrateMode: args["bitrateMode"] as? String
            )
            startRecording(name: name, result: result)

        case "pushFrame":
            guard let args     = call.arguments as? [String: Any],
                  let data     = args["pixels"] as? FlutterStandardTypedData,
                  let tsMillis = args["timestampMs"] as? Int64
            else {
                return result(FlutterError(code: "INVALID_ARGS", message: "Expected pixels, timestampMs", details: nil))
            }
            let timestamp = CMTimeMake(value: tsMillis, timescale: 1000)
            pushFrame(rawData: data.data, timestamp: timestamp, result: result)

        case "stopRecording":
            stopRecording(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(value, max))
    }

    private func buildEncoderConfig(
        targetFps: Int?,
        bitrateBps: Int?,
        iFrameIntervalSec: Int?,
        bitrateMode: String?
    ) -> EncoderConfig {
        let normalizedMode = (bitrateMode ?? EncoderConfig.default.bitrateMode).lowercased()
        let safeMode = (normalizedMode == "vbr" || normalizedMode == "cbr")
            ? normalizedMode
            : EncoderConfig.default.bitrateMode

        return EncoderConfig(
            targetFps: clamp(targetFps ?? EncoderConfig.default.targetFps, min: 1, max: 120),
            bitrateBps: clamp(bitrateBps ?? EncoderConfig.default.bitrateBps, min: 100_000, max: 100_000_000),
            iFrameIntervalSec: clamp(iFrameIntervalSec ?? EncoderConfig.default.iFrameIntervalSec, min: 1, max: 10),
            bitrateMode: safeMode
        )
    }

    private func makeVideoSettings() -> [String: Any] {
        let maxKeyFrameInterval = Swift.max(1, encoderConfig.targetFps * encoderConfig.iFrameIntervalSec)
        let compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: encoderConfig.bitrateBps,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoMaxKeyFrameIntervalKey: maxKeyFrameInterval,
            AVVideoExpectedSourceFrameRateKey: encoderConfig.targetFps,
            AVVideoAllowFrameReorderingKey: false
        ]

        if encoderConfig.bitrateMode == "vbr" {
            NSLog("[flutter_widget_recorder] iOS AVAssetWriter does not expose explicit CBR/VBR mode control. Requested bitrateMode=vbr is accepted but not directly applied.")
        }

        return [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]
    }

    private func logEffectiveEncoderSettings() {
        NSLog(
            "[flutter_widget_recorder] Encoder config iOS: width=\(pixelWidth), height=\(pixelHeight), fps=\(encoderConfig.targetFps), bitrateBps=\(encoderConfig.bitrateBps), iFrameIntervalSec=\(encoderConfig.iFrameIntervalSec), bitrateMode=\(encoderConfig.bitrateMode)"
        )
    }

    // MARK: — startRecording
    private func startRecording(name: String, result: @escaping FlutterResult) {
        guard !isRecording else {
            return result(FlutterError(code: "ALREADY_RECORDING", message: "Recording already in progress", details: nil))
        }
        isRecording = true; firstTimestamp = nil

        // prepare file
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outURL = docs.appendingPathComponent("\(name).mp4")
        videoOutputURL = outURL
        
        // Remove existing file if any
        if FileManager.default.fileExists(atPath: outURL.path) {
            do {
                try FileManager.default.removeItem(at: outURL)
            } catch {
                isRecording = false
                return result(FlutterError(code: "FILE_ERROR", message: "Cannot remove existing file", details: error.localizedDescription))
            }
        }

        // create writer
        do {
            videoWriter = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        } catch {
            isRecording = false
            return result(FlutterError(code: "WRITER_ERROR", message: "Cannot create AVAssetWriter", details: error.localizedDescription))
        }

        let videoSettings = makeVideoSettings()

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        input.transform = CGAffineTransform(rotationAngle: 0)
        
        guard let writer = videoWriter, writer.canAdd(input) else {
            isRecording = false
            return result(FlutterError(code: "INPUT_ERROR", message: "Cannot add input", details: nil))
        }

        // adaptor for YUV420 (NV12)
        let yuvAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: pixelWidth,
            kCVPixelBufferHeightKey as String: pixelHeight,
            kCVPixelBufferBytesPerRowAlignmentKey as String: 16
        ]
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: yuvAttrs
        )

        writer.add(input)
        videoWriterInput = input

        // start
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        logEffectiveEncoderSettings()

        result(true)
    }

    // MARK: — pushFrame
    private func pushFrame(rawData: Data, timestamp: CMTime, result: @escaping FlutterResult) {
        guard isRecording else {
            return result(FlutterError(code: "NOT_RECORDING", message: "Not recording", details: nil))
        }

        // Check writer status and recreate if needed
        if videoWriter == nil || videoWriter?.status == .failed || videoWriter?.status == .unknown {
            guard let url = videoOutputURL else {
                return result(FlutterError(code: "NO_URL", message: "No output URL", details: nil))
            }
            
            // Clean up old writer if exists
            if let oldWriter = videoWriter {
                oldWriter.cancelWriting()
                videoWriter = nil
                videoWriterInput = nil
                pixelBufferAdaptor = nil
            }
            
            // Remove existing file if any
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    isRecording = false
                    return result(FlutterError(code: "FILE_ERROR", message: "Cannot remove existing file", details: error.localizedDescription))
                }
            }
            
            // Create new writer
            do {
                videoWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
            } catch {
                isRecording = false
                return result(FlutterError(code: "WRITER_ERROR", message: "Cannot create AVAssetWriter", details: error.localizedDescription))
            }

            let videoSettings = self.makeVideoSettings()

            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true
            input.transform = CGAffineTransform(rotationAngle: 0)
            
            guard let writer = videoWriter, writer.canAdd(input) else {
                isRecording = false
                return result(FlutterError(code: "INPUT_ERROR", message: "Cannot add input", details: nil))
            }

            // adaptor for YUV420 (NV12)
            let yuvAttrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: pixelWidth,
                kCVPixelBufferHeightKey as String: pixelHeight,
                kCVPixelBufferBytesPerRowAlignmentKey as String: 16
            ]
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: yuvAttrs
            )

            writer.add(input)
            videoWriterInput = input

            // start
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            firstTimestamp = timestamp
            self.logEffectiveEncoderSettings()
        }

        guard let writer = videoWriter,
              let input = videoWriterInput,
              let adaptor = pixelBufferAdaptor
        else {
            return result(FlutterError(code: "NOT_READY", message: "Not initialized", details: nil))
        }

        // Check writer status before proceeding
        if writer.status != .writing {
            let status = writer.status.rawValue
            let error = writer.error?.localizedDescription ?? "Unknown"
            return result(FlutterError(code: "WRITER_ERROR", message: "Writer not in writing state: status=\(status), error=\(error)", details: nil))
        }

        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                // timestamp
                var pts = CMTime.zero
                if let first = self.firstTimestamp {
                    pts = CMTimeSubtract(timestamp, first)
                } else {
                    self.firstTimestamp = timestamp
                }

                // Calculate actual stride from input data
                let actualStride = rawData.count / self.frameHeight
                if actualStride % 4 != 0 {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "INVALID_STRIDE", message: "Invalid stride: \(actualStride)", details: nil))
                    }
                    return
                }

                // BGRA pixel buffer
                var bgraBuf: CVPixelBuffer?
                let bgraAttrs: [String: Any] = [
                    kCVPixelBufferCGImageCompatibilityKey as String: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                    kCVPixelBufferWidthKey as String: self.pixelWidth,
                    kCVPixelBufferHeightKey as String: self.pixelHeight,
                    kCVPixelBufferBytesPerRowAlignmentKey as String: 16,
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                let status = CVPixelBufferCreate(kCFAllocatorDefault, self.pixelWidth, self.pixelHeight,
                                     kCVPixelFormatType_32BGRA, bgraAttrs as CFDictionary, &bgraBuf)
                guard status == kCVReturnSuccess, let bgra = bgraBuf else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "BUFFER_CREATE_FAILED", message: "Failed to create pixel buffer", details: nil))
                    }
                    return
                }

                CVPixelBufferLockBaseAddress(bgra, [])
                let dst = CVPixelBufferGetBaseAddress(bgra)!
                let dstStride = CVPixelBufferGetBytesPerRow(bgra)
                rawData.withUnsafeBytes { srcPtr in
                    let base = srcPtr.bindMemory(to: UInt8.self).baseAddress!
                    for row in 0..<self.frameHeight {
                        let d = dst.advanced(by: row*dstStride).assumingMemoryBound(to: UInt8.self)
                        let s = base.advanced(by: row*actualStride)
                        // Convert RGBA to BGRA by swapping R and B channels
                        for i in stride(from: 0, to: self.frameWidth*4, by: 4) {
                            d[i] = s[i+2]     // B = R
                            d[i+1] = s[i+1]   // G = G
                            d[i+2] = s[i]     // R = B
                            d[i+3] = s[i+3]   // A = A
                        }
                        // Fill the rest of the row with zeros if needed
                        if self.pixelWidth > self.frameWidth {
                            for i in stride(from: self.frameWidth*4, to: self.pixelWidth*4, by: 4) {
                                d[i] = 0       // B
                                d[i+1] = 0     // G
                                d[i+2] = 0     // R
                                d[i+3] = 0     // A
                            }
                        }
                    }
                    // Fill the rest of the buffer with zeros if needed
                    if self.pixelHeight > self.frameHeight {
                        for row in self.frameHeight..<self.pixelHeight {
                            let d = dst.advanced(by: row*dstStride).assumingMemoryBound(to: UInt8.self)
                            for i in stride(from: 0, to: self.pixelWidth*4, by: 4) {
                                d[i] = 0       // B
                                d[i+1] = 0     // G
                                d[i+2] = 0     // R
                                d[i+3] = 0     // A
                            }
                        }
                    }
                }
                CVPixelBufferUnlockBaseAddress(bgra, [])

                // Create YUV buffer directly
                var yuvBuf: CVPixelBuffer?
                let yuvAttrs: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                    kCVPixelBufferWidthKey as String: self.pixelWidth,
                    kCVPixelBufferHeightKey as String: self.pixelHeight,
                    kCVPixelBufferBytesPerRowAlignmentKey as String: 16
                ]
                let yuvStatus = CVPixelBufferCreate(kCFAllocatorDefault, self.pixelWidth, self.pixelHeight,
                                     kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, yuvAttrs as CFDictionary, &yuvBuf)
                guard yuvStatus == kCVReturnSuccess, let yuv = yuvBuf else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "YUV_CREATE_FAILED", message: "Failed to create YUV buffer", details: nil))
                    }
                    return
                }

                // convert via CoreImage
                let ciImage = CIImage(cvPixelBuffer: bgra)
                self.ciContext.render(ciImage, to: yuv)

                // Check writer status again before appending
                if writer.status != .writing {
                    let status = writer.status.rawValue
                    let error = writer.error?.localizedDescription ?? "Unknown"
                    DispatchQueue.main.async {
                        result(FlutterError(code: "WRITER_ERROR", message: "Writer failed before append: status=\(status), error=\(error)", details: nil))
                    }
                    return
                }

                // append
                if input.isReadyForMoreMediaData {
                    let ok = adaptor.append(yuv, withPresentationTime: pts)
                    if !ok {
                        let err = writer.error?.localizedDescription ?? "Unknown"
                        DispatchQueue.main.async {
                            result(FlutterError(code: "APPEND_FAILED", message: "Failed to append pixel buffer: \(err)", details: nil))
                        }
                        return
                    }
                    DispatchQueue.main.async { result(true) }
                } else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "NOT_READY", message: "Input not ready for more media data", details: nil))
                    }
                }
            }
        }
    }

    // MARK: — stopRecording
    private func stopRecording(result: @escaping FlutterResult) {
        guard isRecording, let writer = videoWriter, let input = videoWriterInput else {
            return result(FlutterError(code: "NOT_RECORDING", message: "No recording in progress", details: nil))
        }
        isRecording = false
        input.markAsFinished()
        writer.finishWriting { [weak self] in
            DispatchQueue.main.async {
                if let err = writer.error {
                    result(FlutterError(code: "FINISH_ERR", message: "Finish failed", details: err.localizedDescription))
                } else {
                    result(self?.videoOutputURL?.path)
                }
            }
            self?.videoWriter = nil
            self?.videoWriterInput = nil
            self?.pixelBufferAdaptor = nil
            self?.firstTimestamp = nil
        }
    }
}

