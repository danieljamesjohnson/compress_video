import Foundation

/// Pure preset/explicit-target/target-size resolution shared by the compress path and the
/// estimate path.
///
/// No AVFoundation, CoreMedia, CoreVideo, Flutter or FlutterMacOS import -- exercisable as
/// plain Swift with no simulator, exactly like `MediaMath`, because `estimate()` must be able
/// to call the same resolution the real compress path uses without ever touching a decoder.
///
/// Mirrors Android's `SizeGuard.kt` line-for-line: same rule numbering (1-7), same field
/// names, same constants, same `wouldTransmux`/`wouldUseOriginal` predicates. A divergence
/// between the two engines is a port bug, not a platform difference, until proven otherwise --
/// `SizeGuard.kt` is the shipped reference; do not edit it or its expected values to make this
/// port agree (03-02-PLAN.md's prohibition).
enum SizeGuard {
  /// The probed facts about the input file `SizeGuard` needs. `nil` on any optional field
  /// means "the platform could not determine this" -- never a sentinel `0` or empty string
  /// (mirroring `MediaInfoMessage`'s own contract).
  struct InputInfo {
    /// Displayed (rotation-corrected) width, in pixels.
    let displayedWidthPx: Int
    /// Displayed (rotation-corrected) height, in pixels.
    let displayedHeightPx: Int
    /// Unsigned clockwise rotation, in degrees, as reported before display-correction.
    let rotationDegrees: Int
    /// Duration of the input, in milliseconds.
    let durationMs: Int64
    /// Size of the input file, in bytes.
    let sizeBytes: Int64
    /// Normalised video codec token (see `MediaMath.normalizeCodec`).
    let videoCodec: String
    /// Average video-track bitrate, in bits per second, or `nil` when unknown.
    let videoBitrateBps: Int64?
    /// Video frame rate, in frames per second, or `nil` when unknown.
    let frameRateFps: Double?
    /// Whether the input has at least one audio track.
    let hasAudio: Bool
    /// Normalised audio codec token, or `nil` when `hasAudio` is `false` or unknown.
    let audioCodec: String?
    /// Average audio-track bitrate, in bits per second, or `nil` when unknown.
    let audioBitrateBps: Int64?

    init(
      displayedWidthPx: Int,
      displayedHeightPx: Int,
      rotationDegrees: Int,
      durationMs: Int64,
      sizeBytes: Int64,
      videoCodec: String,
      videoBitrateBps: Int64?,
      frameRateFps: Double?,
      hasAudio: Bool,
      audioCodec: String?,
      audioBitrateBps: Int64?
    ) {
      self.displayedWidthPx = displayedWidthPx
      self.displayedHeightPx = displayedHeightPx
      self.rotationDegrees = rotationDegrees
      self.durationMs = durationMs
      self.sizeBytes = sizeBytes
      self.videoCodec = videoCodec
      self.videoBitrateBps = videoBitrateBps
      self.frameRateFps = frameRateFps
      self.hasAudio = hasAudio
      self.audioCodec = audioCodec
      self.audioBitrateBps = audioBitrateBps
    }
  }

  /// The resolved request `SizeGuard` resolves against an `InputInfo`.
  ///
  /// `maxLongSidePx` and `videoBitrateBps` are explicit-override-or-`nil` -- `nil` means "the
  /// caller did not set this field", which is what lets rule 6 tell an explicit bitrate
  /// request apart from one that must fall back to preset scaling. `presetMaxLongSidePx` and
  /// `presetVideoBitrateBps` are always the selected preset's own nominal values, sent
  /// regardless of any override, because they are the fixed reference the bitrate-scaling
  /// formula (rule 6) divides by -- an override changes the *target*, never the *reference*.
  struct Options {
    /// Explicit cap on the output's longer displayed side, in pixels, or `nil`.
    let maxLongSidePx: Int64?
    /// Explicit target video bitrate, in bits per second, or `nil`.
    let videoBitrateBps: Int64?
    /// Explicit target output size, in megabytes (1,000,000 bytes each), or `nil`.
    let targetSizeMb: Double?
    /// The selected preset's own nominal long-side cap, in pixels. Always set.
    let presetMaxLongSidePx: Int64
    /// The selected preset's own nominal video bitrate, in bits per second. Always set.
    let presetVideoBitrateBps: Int64
    /// Cap on the output's frame rate, in frames per second. Never upscales.
    let maxFps: Int64
    /// Whether the audio track is being removed entirely.
    let audioStripped: Bool
    /// Whether the request is `AudioModeMessage.passthrough` -- distinct from
    /// `audioStripped` (`strip`) and a forced re-encode (`reencode`). `wouldTransmux`'s
    /// audio-mode condition is only satisfied by an explicit passthrough request; a caller
    /// asking to strip or re-encode audio must not be told the job would remux.
    let audioPassthroughRequested: Bool
    /// Explicit requested audio bitrate (only meaningful for a re-encode), or `nil`.
    let requestedAudioBitrateBps: Int64?
    /// Start of the trim range, in milliseconds, or `nil` for the start of the input.
    let trimStartMs: Int64?
    /// End of the trim range, in milliseconds, or `nil` for the end of the input.
    let trimEndMs: Int64?

    init(
      maxLongSidePx: Int64?,
      videoBitrateBps: Int64?,
      targetSizeMb: Double?,
      presetMaxLongSidePx: Int64,
      presetVideoBitrateBps: Int64,
      maxFps: Int64,
      audioStripped: Bool,
      audioPassthroughRequested: Bool,
      requestedAudioBitrateBps: Int64?,
      trimStartMs: Int64?,
      trimEndMs: Int64?
    ) {
      self.maxLongSidePx = maxLongSidePx
      self.videoBitrateBps = videoBitrateBps
      self.targetSizeMb = targetSizeMb
      self.presetMaxLongSidePx = presetMaxLongSidePx
      self.presetVideoBitrateBps = presetVideoBitrateBps
      self.maxFps = maxFps
      self.audioStripped = audioStripped
      self.audioPassthroughRequested = audioPassthroughRequested
      self.requestedAudioBitrateBps = requestedAudioBitrateBps
      self.trimStartMs = trimStartMs
      self.trimEndMs = trimEndMs
    }
  }

  /// The resolved plan: everything the compress engine needs to build its reader/writer
  /// pipeline without computing any of its own scaling arithmetic.
  struct Plan: Equatable {
    /// Resolved output width, in pixels. Always even and at least 16.
    let targetWidthPx: Int
    /// Resolved output height, in pixels. Always even and at least 16.
    let targetHeightPx: Int
    /// Resolved output frame rate, in frames per second. Never above the input's own.
    let effectiveFps: Int
    /// Resolved video bitrate, in bits per second. Never above the input's own, when known.
    let videoBitrateBps: Int64
    /// Resolved audio bitrate, in bits per second. `0` when the audio is stripped.
    let audioBitrateBps: Int64
    /// Resolved output duration, in milliseconds -- the trimmed duration when trimmed.
    let outputDurationMs: Int64
    /// Predicted output file size, in bytes, including estimated container overhead. Exactly
    /// `InputInfo.sizeBytes` when `wouldTransmux` is `true`, since a remux copies the same
    /// samples rather than re-encoding them.
    let predictedOutputBytes: Int64
    /// Whether the engine would be asked to remux (container copy, no video re-encode) rather
    /// than transcode. A pre-flight recommendation for which operation is attempted, and which
    /// encoder settings to build -- NOT a guarantee about the bytes the caller ultimately
    /// receives. The real output is always re-verified against `InputInfo.sizeBytes` after the
    /// job runs (see `wouldUseOriginal`'s own note), whichever operation was attempted, and a
    /// remux whose real output is not smaller than the input is discarded exactly like a real
    /// encode would be -- CORE-05 describes the file the caller receives, not the operation
    /// that was attempted.
    let wouldTransmux: Bool
    /// Whether the engine should skip attempting an encode at all and copy the original input
    /// to the output path instead, because `wouldTransmux` is `false` and
    /// `predictedOutputBytes` is already greater than or equal to `InputInfo.sizeBytes` --
    /// equality counts as "would not help". This is the PRE-flight check only, deciding
    /// whether it is worth even attempting an operation; it is `false` whenever `wouldTransmux`
    /// is `true` because a remux is cheap enough, and often successful enough, that it is
    /// always worth attempting rather than skipped outright. The engine's POST-check, applied
    /// unconditionally to whatever real bytes an attempted remux OR a real encode actually
    /// produced, is a separate, later decision this field does not by itself determine -- a
    /// `false` here does not mean the final returned file can never be the original; it means
    /// only that an attempt is worth making.
    let wouldUseOriginal: Bool
  }

  /// The video codec token that satisfies `wouldTransmux`'s codec condition.
  private static let videoCodecH264 = "h264"

  /// The audio codec token that satisfies `wouldTransmux`'s audio-codec condition.
  private static let audioCodecAAC = "aac"

  // The AAC encoder's own advertised bitrate range -- mirrors Android's own live-measured
  // `c2.android.aac.encoder` range (`SizeGuard.kt`'s own comment): a requested or fallback
  // audio bitrate outside this range would either be silently clamped by the codec or fail to
  // initialise.
  private static let minAudioBitrateBps: Int64 = 8000
  private static let maxAudioBitrateBps: Int64 = 960000
  private static let defaultAudioBitrateBps: Int64 = 128000

  // This project's own floor, so a degenerate targetSizeMb/preset combination never asks for a
  // visually useless bitrate.
  private static let videoBitrateFloorBps: Int64 = 200000

  private static let nominalPresetFps = 30.0
  private static let bytesPerMegabyte = 1_000_000.0
  private static let bitsPerByte = 8.0
  private static let millisPerSecond = 1000.0

  // 3 percent mux overhead: a targetSizeMb request reserves this fraction of the requested
  // size for container/muxing overhead before dividing the rest between video and audio
  // bitrate.
  private static let muxOverheadFactor = 0.97

  // The inverse direction: predicting a file's size from a resolved bitrate adds back an
  // estimated 3 percent for container overhead.
  private static let containerOverheadFactor = 1.03

  /// Resolves `options` against `input` into a `Plan`, applying every rule below in order.
  static func resolve(input: InputInfo, options: Options) -> Plan {
    // Rule 1: effectiveLongSidePx never exceeds the input's own displayed long side.
    let inputLongSidePx = Int64(max(input.displayedWidthPx, input.displayedHeightPx))
    let requestedLongSidePx = options.maxLongSidePx ?? options.presetMaxLongSidePx
    let effectiveLongSidePx = min(requestedLongSidePx, inputLongSidePx)

    // Rule 2.
    let scale = Double(effectiveLongSidePx) / Double(inputLongSidePx)

    // Rule 3: both dimensions rounded down to even, floored at 16.
    let targetWidthPx = MediaMath.floorToEvenMin16(Double(input.displayedWidthPx) * scale)
    let targetHeightPx = MediaMath.floorToEvenMin16(Double(input.displayedHeightPx) * scale)

    // Rule 4: never upscale frame rate either. An unknown input frame rate uses maxFps
    // unchanged, per the rule's own stated fallback. Half-up rounding (via
    // MediaMath.roundHalfUpMs, the same floor(value + 0.5) rule Android's roundFpsHalfUp uses)
    // so a fractional source rate like NTSC's 29.97 compares correctly against an integer cap.
    let inputFpsRounded: Int? = input.frameRateFps.map { Int(MediaMath.roundHalfUpMs($0)) }
    let effectiveFps = min(Int(options.maxFps), inputFpsRounded ?? Int(options.maxFps))

    // Trim-aware output duration, needed by rules 6 and 7.
    let trimStartMs = options.trimStartMs ?? 0
    let trimEndMs = options.trimEndMs ?? input.durationMs
    let outputDurationMs = max(trimEndMs - trimStartMs, 0)
    let outputDurationSeconds = Double(outputDurationMs) / millisPerSecond

    // Rule 5: audio bitrate, clamped into the AAC encoder's own advertised range.
    let audioBitrateBps: Int64
    if options.audioStripped {
      audioBitrateBps = 0
    } else {
      let requestedOrFallback =
        options.requestedAudioBitrateBps ?? input.audioBitrateBps ?? defaultAudioBitrateBps
      audioBitrateBps = min(max(requestedOrFallback, minAudioBitrateBps), maxAudioBitrateBps)
    }

    // Rule 6: video bitrate, in precedence order, then capped at the input's own bitrate in
    // every branch.
    var videoBitrateBps: Int64
    if let explicitVideoBitrateBps = options.videoBitrateBps {
      videoBitrateBps = explicitVideoBitrateBps
    } else if let targetSizeMb = options.targetSizeMb {
      // A durationless input (missing/zero duration metadata) would otherwise divide by
      // zero here. There is no meaningful per-second target bitrate for zero output
      // duration, so fall back to the same floor every other branch is already clamped to
      // (mirrors Android's WR-02 fix).
      if outputDurationSeconds <= 0.0 {
        videoBitrateBps = videoBitrateFloorBps
      } else {
        let targetTotalBitrateBps =
          targetSizeMb * bytesPerMegabyte * bitsPerByte / outputDurationSeconds
          * muxOverheadFactor
        let targetVideoBitrateBps = targetTotalBitrateBps - Double(audioBitrateBps)
        videoBitrateBps = max(Int64(targetVideoBitrateBps), videoBitrateFloorBps)
      }
    } else {
      // A preset applied to a source smaller than the preset's own long side does not spend
      // the full preset bitrate on it.
      let longSideRatio = Double(effectiveLongSidePx) / Double(options.presetMaxLongSidePx)
      let fpsRatio = Double(effectiveFps) / nominalPresetFps
      let scaledBps =
        Double(options.presetVideoBitrateBps) * longSideRatio * longSideRatio * fpsRatio
      videoBitrateBps = max(Int64(scaledBps), videoBitrateFloorBps)
    }
    if let inputVideoBitrateBps = input.videoBitrateBps {
      videoBitrateBps = min(videoBitrateBps, inputVideoBitrateBps)
    }

    // Transmux predicate: every condition must hold. Integer cross-multiplication (`* 100` /
    // `* 115`) for the bitrate headroom check, not floating-point multiplication by 1.15, so a
    // value placed exactly at the boundary in a test is never at the mercy of
    // binary-floating-point rounding.
    let noTrimRequested = options.trimStartMs == nil && options.trimEndMs == nil
    let wouldTransmux =
      input.videoCodec == videoCodecH264
      && (!input.hasAudio || input.audioCodec == audioCodecAAC)
      && options.audioPassthroughRequested
      && noTrimRequested
      && inputLongSidePx <= effectiveLongSidePx
      && (inputFpsRounded == nil || inputFpsRounded! <= Int(options.maxFps))
      && input.videoBitrateBps != nil
      && input.videoBitrateBps! * 100 <= videoBitrateBps * 115

    // Rule 7. A remux copies the same samples into a new container, so its predicted output is
    // exactly the input's own byte count rather than a bitrate*duration estimate.
    let predictedOutputBytes: Int64
    if wouldTransmux {
      predictedOutputBytes = input.sizeBytes
    } else {
      let predictedBytes =
        Double(videoBitrateBps + audioBitrateBps) * outputDurationSeconds / bitsPerByte
        * containerOverheadFactor
      predictedOutputBytes = Int64(predictedBytes.rounded(.up))
    }

    // Never-larger pre-check predicate: decided second, only when the plan is not already a
    // remux. Equality counts as "would not help" -- a predicted output exactly matching the
    // input size gains nothing but a re-encode's generation loss.
    let wouldUseOriginal = !wouldTransmux && predictedOutputBytes >= input.sizeBytes

    return Plan(
      targetWidthPx: targetWidthPx,
      targetHeightPx: targetHeightPx,
      effectiveFps: effectiveFps,
      videoBitrateBps: videoBitrateBps,
      audioBitrateBps: audioBitrateBps,
      outputDurationMs: outputDurationMs,
      predictedOutputBytes: predictedOutputBytes,
      wouldTransmux: wouldTransmux,
      wouldUseOriginal: wouldUseOriginal
    )
  }
}
