package com.tsitser.flutter_widget_recorder

import android.content.Context
import android.media.*
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

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

    private var encoderThread: HandlerThread? = null
    private var encoderHandler: Handler? = null
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private val isProcessingFrame = AtomicBoolean(false)
    private var nv12Buffer: ByteArray? = null

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
            firstTimestamp = 0
            isProcessingFrame.set(false)

            nv12Buffer = ByteArray(pixelWidth * pixelHeight * 3 / 2).also { buf ->
                val yPlaneSize = pixelWidth * pixelHeight
                buf.fill(16.toByte(), 0, yPlaneSize)
                buf.fill(128.toByte(), yPlaneSize, buf.size)
            }

            encoderThread = HandlerThread("WidgetRecorderEncoder").also { it.start() }
            encoderHandler = Handler(encoderThread!!.looper)

            isRecording.set(true)
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
                "frameWidth=$frameWidth, frameHeight=$frameHeight, " +
                "fps=${config.targetFps}, bitrateBps=${config.bitrateBps}, " +
                "iFrameIntervalSec=${config.iFrameIntervalSec}, bitrateMode=${config.bitrateModeName()}",
        )
    }

    private fun pushFrame(pixels: ByteArray, timestampMs: Long, result: Result) {
        if (!isRecording.get()) {
            result.error("NOT_RECORDING", "Not recording", null)
            return
        }

        if (!isProcessingFrame.compareAndSet(false, true)) {
            result.success(true)
            return
        }

        encoderHandler?.post {
            try {
                encodeFrame(pixels, timestampMs)
            } catch (e: Exception) {
                Log.e(TAG, "Error encoding frame", e)
            } finally {
                isProcessingFrame.set(false)
            }
        }

        result.success(true)
    }

    private fun encodeFrame(pixels: ByteArray, timestampMs: Long) {
        val codec = mediaCodec ?: return
        val muxer = mediaMuxer ?: return
        val nv12 = nv12Buffer ?: return

        if (firstTimestamp == 0L) {
            firstTimestamp = timestampMs
        }

        convertRGBAtoNV12(pixels, frameWidth, frameHeight, pixelWidth, pixelHeight, nv12)

        val inputBufferIndex = codec.dequeueInputBuffer(10000)
        if (inputBufferIndex >= 0) {
            val inputBuffer = codec.getInputBuffer(inputBufferIndex)
            inputBuffer?.clear()
            inputBuffer?.put(nv12, 0, nv12.size)
            val presentationTimeUs = (timestampMs - firstTimestamp) * 1000
            codec.queueInputBuffer(inputBufferIndex, 0, nv12.size, presentationTimeUs, 0)
        }

        drainOutputBuffers(codec, muxer, false)
    }

    private fun drainOutputBuffers(codec: MediaCodec, muxer: MediaMuxer, endOfStream: Boolean) {
        val bufferInfo = MediaCodec.BufferInfo()
        val timeoutUs: Long = if (endOfStream) 10000 else 0

        while (true) {
            val index = codec.dequeueOutputBuffer(bufferInfo, timeoutUs)

            when {
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (videoTrackIndex < 0) {
                        videoTrackIndex = muxer.addTrack(codec.outputFormat)
                        muxer.start()
                    }
                }
                index >= 0 -> {
                    if (videoTrackIndex < 0) {
                        videoTrackIndex = muxer.addTrack(codec.outputFormat)
                        muxer.start()
                    }

                    val outputBuffer = codec.getOutputBuffer(index)
                    if (outputBuffer != null && bufferInfo.size > 0) {
                        outputBuffer.position(bufferInfo.offset)
                        outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSampleData(videoTrackIndex, outputBuffer, bufferInfo)
                    }

                    codec.releaseOutputBuffer(index, false)

                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        return
                    }
                }
                else -> return
            }
        }
    }

    private fun stopRecording(result: Result) {
        if (!isRecording.get()) {
            result.error("NOT_RECORDING", "No recording in progress", null)
            return
        }

        isRecording.set(false)

        val handler = encoderHandler
        if (handler == null) {
            finalizeAndRespond(result)
            return
        }

        handler.post {
            try {
                val codec = mediaCodec
                val muxer = mediaMuxer

                if (codec != null && muxer != null) {
                    val eosIndex = codec.dequeueInputBuffer(10000)
                    if (eosIndex >= 0) {
                        codec.queueInputBuffer(
                            eosIndex, 0, 0, 0,
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                        )
                    }
                    drainOutputBuffers(codec, muxer, true)

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

                val path = outputFile?.absolutePath
                mainHandler.post {
                    result.success(path)
                    cleanupState()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping recording", e)
                mainHandler.post {
                    result.error("STOP_ERROR", "Failed to stop recording: ${e.message}", null)
                    cleanupState()
                }
            }
        }
    }

    private fun finalizeAndRespond(result: Result) {
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

            result.success(outputFile?.absolutePath)
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping recording", e)
            result.error("STOP_ERROR", "Failed to stop recording: ${e.message}", null)
        } finally {
            cleanupState()
        }
    }

    private fun cleanupState() {
        videoTrackIndex = -1
        firstTimestamp = 0
        effectiveEncoderConfig = null
        nv12Buffer = null
        isProcessingFrame.set(false)

        encoderThread?.quitSafely()
        encoderThread = null
        encoderHandler = null
    }

    private fun cleanup() {
        mediaCodec?.release()
        mediaCodec = null
        mediaMuxer?.release()
        mediaMuxer = null
        isRecording.set(false)
        cleanupState()
    }

    /**
     * Converts RGBA pixel data to NV12 (YUV420 semi-planar) using BT.601 limited-range
     * (Y: 16-235, UV: 16-240) fixed-point integer arithmetic. This matches the iOS
     * pipeline which uses kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange and the H.264
     * default assumption of limited-range YUV.
     */
    private fun convertRGBAtoNV12(
        rgba: ByteArray,
        width: Int,
        height: Int,
        stride: Int,
        alignedHeight: Int,
        nv12: ByteArray,
    ) {
        val yPlaneSize = stride * alignedHeight

        for (j in 0 until height) {
            val yRowStart = j * stride
            val rgbaRowStart = j * width * 4

            for (i in 0 until width) {
                val rgbIdx = rgbaRowStart + i * 4
                val r = rgba[rgbIdx].toInt() and 0xff
                val g = rgba[rgbIdx + 1].toInt() and 0xff
                val b = rgba[rgbIdx + 2].toInt() and 0xff

                nv12[yRowStart + i] = (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte()

                if (j % 2 == 0 && i % 2 == 0) {
                    val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                    val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                    val uvIdx = yPlaneSize + (j / 2) * stride + i
                    nv12[uvIdx] = u.toByte()
                    nv12[uvIdx + 1] = v.toByte()
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        cleanup()
    }
}
