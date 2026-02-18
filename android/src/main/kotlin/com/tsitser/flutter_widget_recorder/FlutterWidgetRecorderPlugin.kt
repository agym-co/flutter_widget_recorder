package com.tsitser.flutter_widget_recorder

import android.content.Context
import android.media.*
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/** FlutterWidgetRecorderPlugin */
class FlutterWidgetRecorderPlugin: FlutterPlugin, MethodCallHandler {
    internal data class EncoderConfig(
        val targetFps: Int,
        val bitrateBps: Int,
        val iFrameIntervalSec: Int,
        val bitrateMode: Int,
    ) {
        fun bitrateModeName(): String {
            return when (bitrateMode) {
                MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR -> "vbr"
                MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR -> "cbr"
                else -> "unknown($bitrateMode)"
            }
        }
    }

    companion object {
        private const val TAG = "FlutterWidgetRecorder"

        internal const val DEFAULT_TARGET_FPS = 30
        internal const val DEFAULT_BITRATE_BPS = 2_000_000
        internal const val DEFAULT_I_FRAME_INTERVAL_SEC = 1
        internal const val MIN_TARGET_FPS = 1
        internal const val MAX_TARGET_FPS = 120
        internal const val MIN_BITRATE_BPS = 100_000
        internal const val MAX_BITRATE_BPS = 100_000_000
        internal const val MIN_I_FRAME_INTERVAL_SEC = 1
        internal const val MAX_I_FRAME_INTERVAL_SEC = 10

        private fun clamp(value: Int, min: Int, max: Int): Int {
            return value.coerceIn(min, max)
        }

        internal fun parseBitrateMode(bitrateMode: String?): Int? {
            return when (bitrateMode?.trim()?.lowercase()) {
                "cbr" -> MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR
                "vbr" -> MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR
                else -> null
            }
        }

        internal fun buildEncoderConfig(
            targetFps: Int?,
            bitrateBps: Int?,
            iFrameIntervalSec: Int?,
            bitrateMode: String?,
        ): EncoderConfig {
            return EncoderConfig(
                targetFps = clamp(
                    targetFps ?: DEFAULT_TARGET_FPS,
                    MIN_TARGET_FPS,
                    MAX_TARGET_FPS,
                ),
                bitrateBps = clamp(
                    bitrateBps ?: DEFAULT_BITRATE_BPS,
                    MIN_BITRATE_BPS,
                    MAX_BITRATE_BPS,
                ),
                iFrameIntervalSec = clamp(
                    iFrameIntervalSec ?: DEFAULT_I_FRAME_INTERVAL_SEC,
                    MIN_I_FRAME_INTERVAL_SEC,
                    MAX_I_FRAME_INTERVAL_SEC,
                ),
                bitrateMode = parseBitrateMode(bitrateMode)
                    ?: MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR,
            )
        }
    }

    private lateinit var channel: MethodChannel
    private var mediaCodec: MediaCodec? = null
    private var mediaMuxer: MediaMuxer? = null
    private var videoTrackIndex = -1
    private var isRecording = AtomicBoolean(false)
    private var outputFile: File? = null
    private var firstTimestamp: Long = 0
    private var pixelWidth = 0
    private var pixelHeight = 0
    private var frameWidth = 0
    private var frameHeight = 0
    private lateinit var context: Context
    private var effectiveEncoderConfig: EncoderConfig? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_widget_recorder")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startRecording" -> {
                val name = call.argument<String>("name")
                val width = call.argument<Int>("width")
                val height = call.argument<Int>("height")
                val pixelRatio = call.argument<Double>("pixelRatio")
                val targetFps = call.argument<Number>("targetFps")?.toInt()
                val bitrateBps = call.argument<Number>("bitrateBps")?.toInt()
                val iFrameIntervalSec = call.argument<Number>("iFrameIntervalSec")?.toInt()
                val bitrateMode = call.argument<String>("bitrateMode")

                if (name == null || width == null || height == null || pixelRatio == null) {
                    result.error("INVALID_ARGS", "Expected name, width, height, pixelRatio", null)
                    return
                }

                val unW = (width * pixelRatio).toInt()
                val unH = (height * pixelRatio).toInt()
                frameWidth = unW
                frameHeight = unH
                pixelWidth = ((unW + 15) / 16) * 16
                pixelHeight = ((unH + 15) / 16) * 16

                startRecording(
                    name = name,
                    requestedConfig = buildEncoderConfig(
                        targetFps = targetFps,
                        bitrateBps = bitrateBps,
                        iFrameIntervalSec = iFrameIntervalSec,
                        bitrateMode = bitrateMode,
                    ),
                    result = result,
                )
            }
            "pushFrame" -> {
                val pixels = call.argument<ByteArray>("pixels")
                val timestampMs = call.argument<Long>("timestampMs")

                if (pixels == null || timestampMs == null) {
                    result.error("INVALID_ARGS", "Expected pixels, timestampMs", null)
                    return
                }

                pushFrame(pixels, timestampMs, result)
            }
            "stopRecording" -> {
                stopRecording(result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun startRecording(name: String, requestedConfig: EncoderConfig, result: Result) {
        if (isRecording.get()) {
            result.error("ALREADY_RECORDING", "Recording already in progress", null)
            return
        }

        try {
            outputFile = File(context.filesDir, "$name.mp4")

            if (outputFile?.exists() == true) {
                outputFile?.delete()
            }

            val configuredCodec = createCodecWithFallback(requestedConfig)
            mediaCodec = configuredCodec.first
            effectiveEncoderConfig = configuredCodec.second

            mediaMuxer = MediaMuxer(outputFile?.absolutePath ?: "", MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            videoTrackIndex = -1
            isRecording.set(true)
            firstTimestamp = 0
            logEffectiveEncoderSettings()

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error starting recording", e)
            result.error("START_ERROR", "Failed to start recording: ${e.message}", null)
            cleanup()
        }
    }

    private fun createCodecWithFallback(requestedConfig: EncoderConfig): Pair<MediaCodec, EncoderConfig> {
        val safeDefaults = buildEncoderConfig(
            targetFps = DEFAULT_TARGET_FPS,
            bitrateBps = DEFAULT_BITRATE_BPS,
            iFrameIntervalSec = DEFAULT_I_FRAME_INTERVAL_SEC,
            bitrateMode = "cbr",
        )

        return try {
            createCodec(requestedConfig)
        } catch (primaryError: Exception) {
            if (requestedConfig == safeDefaults) {
                throw primaryError
            }

            Log.w(
                TAG,
                "Requested encoder config failed. Retrying with safe defaults. " +
                    "requestedFps=${requestedConfig.targetFps}, " +
                    "requestedBitrate=${requestedConfig.bitrateBps}, " +
                    "requestedIFrameInterval=${requestedConfig.iFrameIntervalSec}, " +
                    "requestedBitrateMode=${requestedConfig.bitrateModeName()}",
                primaryError,
            )

            try {
                createCodec(safeDefaults)
            } catch (fallbackError: Exception) {
                primaryError.addSuppressed(fallbackError)
                throw primaryError
            }
        }
    }

    private fun createCodec(config: EncoderConfig): Pair<MediaCodec, EncoderConfig> {
        var codec: MediaCodec? = null
        try {
            val mimeType = MediaFormat.MIMETYPE_VIDEO_AVC
            codec = MediaCodec.createEncoderByType(mimeType)
            val format = MediaFormat.createVideoFormat(mimeType, pixelWidth, pixelHeight)
            format.setInteger(MediaFormat.KEY_BIT_RATE, config.bitrateBps)
            format.setInteger(MediaFormat.KEY_FRAME_RATE, config.targetFps)
            format.setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar,
            )
            format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, config.iFrameIntervalSec)

            val effectiveBitrateMode = applySupportedBitrateMode(codec, format, config.bitrateMode)
            val effectiveConfig = config.copy(bitrateMode = effectiveBitrateMode)

            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            return Pair(codec, effectiveConfig)
        } catch (e: Exception) {
            codec?.release()
            throw e
        }
    }

    private fun applySupportedBitrateMode(codec: MediaCodec, format: MediaFormat, requestedMode: Int): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR
        }

        val mimeType = MediaFormat.MIMETYPE_VIDEO_AVC
        val capabilities = codec.codecInfo.getCapabilitiesForType(mimeType).encoderCapabilities

        if (capabilities.isBitrateModeSupported(requestedMode)) {
            format.setInteger(MediaFormat.KEY_BITRATE_MODE, requestedMode)
            return requestedMode
        }

        val fallbackMode = MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR
        if (capabilities.isBitrateModeSupported(fallbackMode)) {
            format.setInteger(MediaFormat.KEY_BITRATE_MODE, fallbackMode)
            return fallbackMode
        }

        return requestedMode
    }

    private fun logEffectiveEncoderSettings() {
        val config = effectiveEncoderConfig ?: return
        Log.i(
            TAG,
            "Encoder config: width=$pixelWidth, height=$pixelHeight, " +
                "fps=${config.targetFps}, bitrateBps=${config.bitrateBps}, " +
                "iFrameIntervalSec=${config.iFrameIntervalSec}, bitrateMode=${config.bitrateModeName()}",
        )
    }

    private fun pushFrame(pixels: ByteArray, timestampMs: Long, result: Result) {
        if (!isRecording.get()) {
            result.error("NOT_RECORDING", "Not recording", null)
            return
        }

        try {
            val codec = mediaCodec ?: throw IllegalStateException("MediaCodec not initialized")
            val muxer = mediaMuxer ?: throw IllegalStateException("MediaMuxer not initialized")

            // Устанавливаем первый timestamp
            if (firstTimestamp == 0L) {
                firstTimestamp = timestampMs
            }

            val yuvData = convertRGBAtoNV12(pixels, frameWidth, frameHeight)

            val inputBufferIndex = codec.dequeueInputBuffer(10000)
            if (inputBufferIndex >= 0) {
                val inputBuffer = codec.getInputBuffer(inputBufferIndex)
                inputBuffer?.clear()
                inputBuffer?.put(yuvData)
                
                val presentationTimeUs = (timestampMs - firstTimestamp) * 1000
                codec.queueInputBuffer(inputBufferIndex, 0, yuvData.size, presentationTimeUs, 0)
            }

            val bufferInfo = MediaCodec.BufferInfo()
            var outputBufferIndex = codec.dequeueOutputBuffer(bufferInfo, 10000)

            while (outputBufferIndex >= 0 || outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                if (outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    if (videoTrackIndex < 0) {
                        val changedFormat = codec.outputFormat
                        videoTrackIndex = muxer.addTrack(changedFormat)
                        muxer.start()
                    }
                    outputBufferIndex = codec.dequeueOutputBuffer(bufferInfo, 0)
                    continue
                }

                if (videoTrackIndex < 0) {
                    val format = codec.outputFormat
                    videoTrackIndex = muxer.addTrack(format)
                    muxer.start()
                }

                val outputBuffer = codec.getOutputBuffer(outputBufferIndex)
                if (outputBuffer != null) {
                    outputBuffer.position(bufferInfo.offset)
                    outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                    muxer.writeSampleData(videoTrackIndex, outputBuffer, bufferInfo)
                }

                codec.releaseOutputBuffer(outputBufferIndex, false)
                outputBufferIndex = codec.dequeueOutputBuffer(bufferInfo, 0)
            }

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error pushing frame", e)
            result.error("PUSH_ERROR", "Failed to push frame: ${e.message}", null)
        }
    }

    private fun stopRecording(result: Result) {
        if (!isRecording.get()) {
            result.error("NOT_RECORDING", "No recording in progress", null)
            return
        }

        try {
            val codec = mediaCodec
            val muxer = mediaMuxer

            if (codec != null && muxer != null) {
                codec.stop()
                codec.release()
                mediaCodec = null

                try {
                    muxer.stop()
                } finally {
                    muxer.release()
                    mediaMuxer = null
                }
            }

            isRecording.set(false)
            result.success(outputFile?.absolutePath)
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping recording", e)
            result.error("STOP_ERROR", "Failed to stop recording: ${e.message}", null)
        } finally {
            cleanup()
        }
    }

    private fun cleanup() {
        mediaCodec?.release()
        mediaCodec = null
        mediaMuxer?.release()
        mediaMuxer = null
        videoTrackIndex = -1
        firstTimestamp = 0
        effectiveEncoderConfig = null
        isRecording.set(false)
    }

    private fun convertRGBAtoNV12(rgba: ByteArray, width: Int, height: Int): ByteArray {
        val ySize = width * height
        val uvSize = (width * height) / 4
        val nv12 = ByteArray(ySize + 2 * uvSize)
        
        var yIndex = 0
        var uvIndex = ySize
        
        for (j in 0 until height) {
            for (i in 0 until width) {
                val rgbIndex = (j * width + i) * 4
                val r = rgba[rgbIndex].toInt() and 0xff
                val g = rgba[rgbIndex + 1].toInt() and 0xff
                val b = rgba[rgbIndex + 2].toInt() and 0xff

                nv12[yIndex++] = ((0.299 * r + 0.587 * g + 0.114 * b).toInt()).toByte()

                if (j % 2 == 0 && i % 2 == 0) {
                    val y = 0.299 * r + 0.587 * g + 0.114 * b
                    val u = 128 + (0.492 * (b - y)).toInt()
                    val v = 128 + (0.877 * (r - y)).toInt()

                    nv12[uvIndex++] = u.coerceIn(0, 255).toByte()
                    nv12[uvIndex++] = v.coerceIn(0, 255).toByte()
                }
            }
        }

        return nv12
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        cleanup()
    }
}
