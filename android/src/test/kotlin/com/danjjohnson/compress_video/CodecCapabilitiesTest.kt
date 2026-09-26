package com.danjjohnson.compress_video

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Pure JVM tests for [CodecCapabilities]'s injectable half -- no emulator, no
 * `android.media.MediaCodecInfo` construction, exactly like [SizeGuardTest]/[ErrorMappingTest].
 * Only [CodecCapabilities.isSoftwareCodecName] and [CodecCapabilities.hasHardwareEncoderFor] are
 * exercised here; the [CodecCapabilities.hasHardwareEncoder]/[CodecCapabilities.supportsHdrEditing]
 * wrappers themselves require a real device or emulator (proven end to end by
 * `hard_inputs_test.dart` instead).
 */
internal class CodecCapabilitiesTest {
    // --- hasHardwareEncoderFor ---

    @Test
    fun hasHardwareEncoderFor_softwareOnlyList_isFalse() {
        val encoders =
            listOf(
                CodecCapabilities.EncoderInfo("c2.android.hevc.encoder", isHardwareAccelerated = false),
                CodecCapabilities.EncoderInfo("OMX.google.hevc.encoder", isHardwareAccelerated = false),
            )
        assertFalse(CodecCapabilities.hasHardwareEncoderFor(encoders))
    }

    @Test
    fun hasHardwareEncoderFor_hardwarePresentList_isTrue() {
        val encoders =
            listOf(
                CodecCapabilities.EncoderInfo("c2.android.hevc.encoder", isHardwareAccelerated = false),
                CodecCapabilities.EncoderInfo("c2.qti.hevc.encoder", isHardwareAccelerated = true),
            )
        assertTrue(CodecCapabilities.hasHardwareEncoderFor(encoders))
    }

    @Test
    fun hasHardwareEncoderFor_emptyList_isFalse() {
        // Literally what compress_video_api35's own EncoderUtil.getSupportedEncoders("video/hevc")
        // returns (04-RESEARCH.md, verified live): zero HEVC encoders of any kind.
        assertFalse(CodecCapabilities.hasHardwareEncoderFor(emptyList()))
    }

    // --- isSoftwareCodecName (D-05's prefix list, the documented pre-API-29 fallback) ---

    @Test
    fun isSoftwareCodecName_c2AndroidPrefix_isTrue() {
        assertTrue(CodecCapabilities.isSoftwareCodecName("c2.android.avc.encoder"))
    }

    @Test
    fun isSoftwareCodecName_omxGooglePrefix_isTrue() {
        assertTrue(CodecCapabilities.isSoftwareCodecName("OMX.google.h264.encoder"))
    }

    @Test
    fun isSoftwareCodecName_c2SwPrefix_isTrue() {
        assertTrue(CodecCapabilities.isSoftwareCodecName("c2.sw.avc.encoder"))
    }

    @Test
    fun isSoftwareCodecName_omxSecPrefix_isTrue() {
        assertTrue(CodecCapabilities.isSoftwareCodecName("OMX.SEC.avc.sw.encoder"))
    }

    @Test
    fun isSoftwareCodecName_hardwareVendorName_isFalse() {
        // A real hardware encoder name must not match any of D-05's prefixes -- prefix matching
        // "is not 100% reliable" (Android's own docs), but a vendor name like this one must not
        // be misclassified as software.
        assertFalse(CodecCapabilities.isSoftwareCodecName("OMX.qcom.video.encoder.avc"))
    }

    // --- supportsHdrEditing's own decision function, driven the same way (both outcomes) ---

    @Test
    fun hasHardwareEncoderFor_hdrEditingSoftwareOnlyList_isFalse() {
        val encoders =
            listOf(
                CodecCapabilities.EncoderInfo("c2.android.hevc.encoder", isHardwareAccelerated = false),
            )
        assertFalse(CodecCapabilities.hasHardwareEncoderFor(encoders))
    }

    @Test
    fun hasHardwareEncoderFor_hdrEditingHardwarePresentList_isTrue() {
        val encoders =
            listOf(
                CodecCapabilities.EncoderInfo("c2.qti.hevc.encoder", isHardwareAccelerated = true),
            )
        assertTrue(CodecCapabilities.hasHardwareEncoderFor(encoders))
    }
}
