package com.tsitser.flutter_widget_recorder

import android.media.MediaCodecInfo
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.Test

internal class FlutterWidgetRecorderPluginTest {
    @Test
    fun parseBitrateMode_supportsCbrAndVbr() {
        assertEquals(
            MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR,
            FlutterWidgetRecorderPlugin.parseBitrateMode("cbr"),
        )
        assertEquals(
            MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR,
            FlutterWidgetRecorderPlugin.parseBitrateMode("vbr"),
        )
        assertEquals(
            MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR,
            FlutterWidgetRecorderPlugin.parseBitrateMode("VBR"),
        )
        assertNull(FlutterWidgetRecorderPlugin.parseBitrateMode("unsupported"))
        assertNull(FlutterWidgetRecorderPlugin.parseBitrateMode(null))
    }

    @Test
    fun buildEncoderConfig_usesDefaultsWhenMissing() {
        val config = FlutterWidgetRecorderPlugin.buildEncoderConfig(
            targetFps = null,
            bitrateBps = null,
            iFrameIntervalSec = null,
            bitrateMode = null,
        )

        assertEquals(FlutterWidgetRecorderPlugin.DEFAULT_TARGET_FPS, config.targetFps)
        assertEquals(FlutterWidgetRecorderPlugin.DEFAULT_BITRATE_BPS, config.bitrateBps)
        assertEquals(
            FlutterWidgetRecorderPlugin.DEFAULT_I_FRAME_INTERVAL_SEC,
            config.iFrameIntervalSec,
        )
        assertEquals(
            MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR,
            config.bitrateMode,
        )
    }

    @Test
    fun buildEncoderConfig_clampsOutOfRangeValues() {
        val config = FlutterWidgetRecorderPlugin.buildEncoderConfig(
            targetFps = 1000,
            bitrateBps = 1,
            iFrameIntervalSec = -10,
            bitrateMode = "vbr",
        )

        assertEquals(FlutterWidgetRecorderPlugin.MAX_TARGET_FPS, config.targetFps)
        assertEquals(FlutterWidgetRecorderPlugin.MIN_BITRATE_BPS, config.bitrateBps)
        assertEquals(FlutterWidgetRecorderPlugin.MIN_I_FRAME_INTERVAL_SEC, config.iFrameIntervalSec)
        assertEquals(
            MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR,
            config.bitrateMode,
        )
    }
}
