package com.danjjohnson.compress_video

import android.media.MediaCodecInfo
import android.os.Build
import androidx.media3.common.ColorInfo
import androidx.media3.common.MimeTypes
import androidx.media3.transformer.EncoderUtil

/**
 * Hardware HEVC and HDR-editing capability probe (CDEC-01, CDEC-03).
 *
 * Structured in two layers, per 04-CONTEXT.md's own "Claude's Discretion" note and
 * 04-PATTERNS.md's injectable-capability-probe pattern (mirroring [SizeGuard]'s own
 * pure-function-over-an-explicit-input shape): pure functions ([isSoftwareCodecName],
 * [hasHardwareEncoderFor]) over an already-fetched [EncoderInfo] list, unit-testable on plain
 * JVM with a fabricated list -- no emulator required, see [CodecCapabilitiesTest] -- and thin
 * wrapper functions ([hasHardwareEncoder], [supportsHdrEditing]) that fetch the real list from
 * [EncoderUtil] and delegate to the pure half.
 *
 * The primary mechanism is [EncoderUtil] itself -- 04-RESEARCH.md's own override of D-05's
 * literal hand-rolled `MediaCodecList` text, because Media3 already ships and tests this, and
 * [EncoderUtil.isHardwareAccelerated] is backed by the platform's own authoritative
 * `MediaCodecInfo.isHardwareAccelerated()` on API 29+. [isSoftwareCodecName]'s prefix list
 * exists only as the documented fallback below API 29, where that platform method does not
 * exist -- it is reachable only from [toEncoderInfo]'s own below-API-29 branch, never the
 * primary mechanism.
 *
 * The wrapper functions execute real `android.os.Build.VERSION.SDK_INT` reads and real
 * [EncoderUtil]/`MediaCodecList` calls that require a real device or emulator to behave
 * correctly against the system's own codec list -- [ErrorMapping]/[SizeGuard]'s own "no
 * android.* import" JVM-testability convention does not extend to this file's wrapper half for
 * that reason. Only the pure half is exercised by [CodecCapabilitiesTest]; [hasHardwareEncoder]
 * and [supportsHdrEditing] are exercised end to end by `hard_inputs_test.dart` on the emulator.
 */
object CodecCapabilities {
    /**
     * A minimal, testable view of one encoder [EncoderUtil.getSupportedEncoders] or
     * [EncoderUtil.getSupportedEncodersForHdrEditing] reported: just the two facts
     * [hasHardwareEncoderFor] needs, decoupled from [android.media.MediaCodecInfo] itself so a
     * JVM unit test can construct one directly rather than needing a real device's codec list.
     */
    data class EncoderInfo(
        val name: String,
        val isHardwareAccelerated: Boolean,
    )

    /**
     * D-05's software-codec name prefixes, carried verbatim. Prefix matching alone "is not 100%
     * reliable" per Android's own docs, which is exactly why [EncoderUtil.isHardwareAccelerated]'s
     * platform-backed API 29+ check ([toEncoderInfo]) is the primary mechanism everywhere it is
     * available -- this list is reachable only from that function's below-API-29 branch.
     */
    private val SOFTWARE_CODEC_NAME_PREFIXES =
        listOf("c2.android.", "OMX.google.", "c2.sw", "OMX.SEC")

    /**
     * Returns `true` when [name] starts with one of D-05's software-codec prefixes
     * (`c2.android.`, `OMX.google.`, `c2.sw`, `OMX.SEC`), `false` otherwise -- including for a
     * hardware vendor name such as `OMX.qcom.video.encoder.avc`, which matches none of them.
     * Pure: no Android import, exercisable on plain JVM with no emulator.
     */
    fun isSoftwareCodecName(name: String): Boolean = SOFTWARE_CODEC_NAME_PREFIXES.any { name.startsWith(it) }

    /**
     * Returns `true` only when at least one entry in [encoders] is hardware-accelerated,
     * `false` for an empty list or a list where every entry is software-only. Pure: no Android
     * import, exercisable on plain JVM against a fabricated [EncoderInfo] list. This is the one
     * decision function both [hasHardwareEncoder] (HEVC opt-in, CDEC-01) and
     * [supportsHdrEditing] (keep-HDR, CDEC-03) delegate to, so both capability questions are
     * proven by the exact same tested logic.
     */
    fun hasHardwareEncoderFor(encoders: List<EncoderInfo>): Boolean = encoders.any { it.isHardwareAccelerated }

    /**
     * Builds an [EncoderInfo] for [info] against [mimeType]: on API 29+,
     * [EncoderUtil.isHardwareAccelerated] answers from the platform's own authoritative flag;
     * below API 29, where that platform method does not exist, falls back to
     * [isSoftwareCodecName] on [info]'s own reported name -- the documented pre-API-29 branch
     * (see class doc). Not itself unit-tested: a real [android.media.MediaCodecInfo] requires a
     * device or emulator to enumerate, and this function's own SDK_INT>=29 branch calls a real
     * platform-backed [EncoderUtil] method that only behaves correctly against a real system
     * codec list.
     */
    private fun toEncoderInfo(
        info: MediaCodecInfo,
        mimeType: String,
    ): EncoderInfo {
        val isHardware =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                EncoderUtil.isHardwareAccelerated(info, mimeType)
            } else {
                !isSoftwareCodecName(info.name)
            }
        return EncoderInfo(info.name, isHardware)
    }

    /**
     * Returns `true` when this device has a hardware-accelerated encoder for [mimeType]
     * (`video/hevc` for CDEC-01's HEVC opt-in), `false` otherwise -- including when
     * [EncoderUtil.getSupportedEncoders] returns an empty list, which is exactly what this
     * project's own `compress_video_api35` emulator returns for `video/hevc` (04-RESEARCH.md,
     * verified live: zero HEVC encoders of any kind).
     */
    fun hasHardwareEncoder(mimeType: String): Boolean =
        hasHardwareEncoderFor(
            EncoderUtil.getSupportedEncoders(mimeType).map { toEncoderInfo(it, mimeType) },
        )

    /**
     * Returns `true` when this device has a hardware-accelerated encoder that supports keeping
     * [colorInfo]'s own HDR characteristics for `video/hevc` (CDEC-03's keep-HDR opt-in),
     * `false` otherwise. Built on [EncoderUtil.getSupportedEncodersForHdrEditing] -- the
     * directly-usable primitive per 04-RESEARCH.md Pattern 3 -- rather than
     * [EncoderUtil.getCodecProfilesForHdrFormat], whose parameter space is deliberately not
     * depended on (04-RESEARCH.md Assumption A4). The returned list is already filtered to
     * encoders Media3 itself judges capable of HDR editing for this exact [colorInfo]; this
     * function additionally requires at least one of THOSE to be hardware-accelerated, since
     * D-07 requires a hardware HEVC 10-bit encoder specifically, not merely HDR-editing support
     * in the abstract.
     */
    fun supportsHdrEditing(colorInfo: ColorInfo): Boolean {
        val encoders = EncoderUtil.getSupportedEncodersForHdrEditing(MimeTypes.VIDEO_H265, colorInfo)
        return hasHardwareEncoderFor(encoders.map { toEncoderInfo(it, MimeTypes.VIDEO_H265) })
    }
}
