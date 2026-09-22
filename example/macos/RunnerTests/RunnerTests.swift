#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import Cocoa
  import FlutterMacOS
#endif
import XCTest

@testable import compress_video

// Pure-Swift unit tests for `MediaMath` and `Arguments`, mirroring Android's
// `MediaMathTest.kt`/`ArgumentsTest.kt` case for case. Run on both the iOS simulator and
// macOS by CI's `apple` job -- kept byte-identical between
// `example/ios/RunnerTests/RunnerTests.swift` and `example/macos/RunnerTests/RunnerTests.swift`
// (diffed in CI) so a rule proven on one Apple platform cannot silently diverge on the other.
//
// See https://developer.apple.com/documentation/xctest for more information about using XCTest.

class RunnerTests: XCTestCase {

  // MARK: - MediaMath.displayedSize

  func testDisplayedSizeRotation0PassesThroughUnchanged() {
    let result = MediaMath.displayedSize(codedWidthPx: 1920, codedHeightPx: 1080, rotationDegrees: 0)
    XCTAssertEqual(result.width, 1920)
    XCTAssertEqual(result.height, 1080)
  }

  func testDisplayedSizeRotation90SwapsWidthAndHeight() {
    let result = MediaMath.displayedSize(codedWidthPx: 1920, codedHeightPx: 1080, rotationDegrees: 90)
    XCTAssertEqual(result.width, 1080)
    XCTAssertEqual(result.height, 1920)
  }

  func testDisplayedSizeRotation180PassesThroughUnchanged() {
    let result = MediaMath.displayedSize(codedWidthPx: 1920, codedHeightPx: 1080, rotationDegrees: 180)
    XCTAssertEqual(result.width, 1920)
    XCTAssertEqual(result.height, 1080)
  }

  func testDisplayedSizeRotation270SwapsWidthAndHeight() {
    let result = MediaMath.displayedSize(codedWidthPx: 1920, codedHeightPx: 1080, rotationDegrees: 270)
    XCTAssertEqual(result.width, 1080)
    XCTAssertEqual(result.height, 1920)
  }

  func testDisplayedSizeSquareCodedFrameStillDecidesByRotationBranch() {
    // Coded width == coded height can't show a numeric difference between the swapped and
    // unswapped result, but this pins that the function still takes the rotation branch
    // (rather than short-circuiting on "width == height") for both a rotated and an
    // unrotated square input.
    let rotated = MediaMath.displayedSize(codedWidthPx: 1080, codedHeightPx: 1080, rotationDegrees: 90)
    XCTAssertEqual(rotated.width, 1080)
    XCTAssertEqual(rotated.height, 1080)
    let unrotated = MediaMath.displayedSize(codedWidthPx: 1080, codedHeightPx: 1080, rotationDegrees: 0)
    XCTAssertEqual(unrotated.width, 1080)
    XCTAssertEqual(unrotated.height, 1080)
  }

  // MARK: - MediaMath.normalizeCodec

  func testNormalizeCodecMapsKnownFourCharacterCodes() {
    XCTAssertEqual(MediaMath.normalizeCodec("avc1"), "h264")
    XCTAssertEqual(MediaMath.normalizeCodec("hvc1"), "hevc")
    XCTAssertEqual(MediaMath.normalizeCodec("hev1"), "hevc")
    XCTAssertEqual(MediaMath.normalizeCodec("av01"), "av1")
    XCTAssertEqual(MediaMath.normalizeCodec("vp09"), "vp9")
  }

  func testNormalizeCodecMapsAndroidMimeTypeToTheSameTokenAsAppleFourCc() {
    // Android's video/avc and Apple's avc1 both normalise to h264 -- the cross-platform
    // contract this function exists to guarantee.
    XCTAssertEqual(MediaMath.normalizeCodec("video/avc"), "h264")
    XCTAssertEqual(MediaMath.normalizeCodec("avc1"), "h264")
  }

  func testNormalizeCodecUnknownCodeMapsToUnknown() {
    XCTAssertEqual(MediaMath.normalizeCodec("xyz9"), "unknown")
  }

  func testNormalizeCodecNilMapsToUnknown() {
    XCTAssertEqual(MediaMath.normalizeCodec(nil), "unknown")
  }

  // MARK: - MediaMath.roundHalfUpMs

  func testRoundHalfUpMsRoundsDownBelowTheHalfBoundary() {
    XCTAssertEqual(MediaMath.roundHalfUpMs(4000.4), 4000)
  }

  func testRoundHalfUpMsRoundsUpAtTheHalfBoundary() {
    XCTAssertEqual(MediaMath.roundHalfUpMs(4000.5), 4001)
  }

  // MARK: - MediaMath.scaledSize

  func testScaledSizeMaxDimensionEqualToTheLongerSideReturnsInputUnchanged() {
    // 1080x1920 is portrait_rot90.mp4's displayed size (corpus/portrait_rot90.expected.json).
    let result = MediaMath.scaledSize(displayedWidthPx: 1080, displayedHeightPx: 1920, maxDimensionPx: 1920)
    XCTAssertEqual(result.width, 1080)
    XCTAssertEqual(result.height, 1920)
  }

  func testScaledSizeMaxDimensionOnePixelBelowTheLongerSideDownscalesPreservingAspectRatio() {
    let result = MediaMath.scaledSize(displayedWidthPx: 1080, displayedHeightPx: 1920, maxDimensionPx: 1919)
    XCTAssertEqual(result.height, 1919)
    XCTAssertEqual(result.width, 1079)
  }

  func testScaledSizeMaxDimensionFarAboveTheLongerSideNeverUpscales() {
    let result = MediaMath.scaledSize(displayedWidthPx: 1080, displayedHeightPx: 1920, maxDimensionPx: 4000)
    XCTAssertEqual(result.width, 1080)
    XCTAssertEqual(result.height, 1920)
  }

  func testScaledSizeNilMaxDimensionReturnsInputUnchanged() {
    let result = MediaMath.scaledSize(displayedWidthPx: 1080, displayedHeightPx: 1920, maxDimensionPx: nil)
    XCTAssertEqual(result.width, 1080)
    XCTAssertEqual(result.height, 1920)
  }

  func testScaledSizeSquareInputCapsBothSidesEqually() {
    let result = MediaMath.scaledSize(displayedWidthPx: 1000, displayedHeightPx: 1000, maxDimensionPx: 500)
    XCTAssertEqual(result.width, 500)
    XCTAssertEqual(result.height, 500)
  }

  // MARK: - MediaMath.clampPositionMs

  func testClampPositionMsBelowDurationPassesThroughUnchanged() {
    XCTAssertEqual(MediaMath.clampPositionMs(3999, durationMs: 4000), 3999)
  }

  func testClampPositionMsExactlyAtDurationPassesThroughUnchanged() {
    XCTAssertEqual(MediaMath.clampPositionMs(4000, durationMs: 4000), 4000)
  }

  func testClampPositionMsAboveDurationClampsDownToDuration() {
    XCTAssertEqual(MediaMath.clampPositionMs(4001, durationMs: 4000), 4000)
  }

  // MARK: - scaledSize + clampPositionMs as composed by the thumbnail path

  func testThumbnailPathComposesDisplayedSizeThenScaledSizeForACappedRequest() {
    // Mirrors Thumbnails.extractThumbnailJpeg's own composition: MediaMath.displayedSize
    // first (rotation-correct), then MediaMath.scaledSize against the requested cap.
    let displayed = MediaMath.displayedSize(codedWidthPx: 1920, codedHeightPx: 1080, rotationDegrees: 90)
    let target = MediaMath.scaledSize(
      displayedWidthPx: displayed.width,
      displayedHeightPx: displayed.height,
      maxDimensionPx: 960
    )
    XCTAssertEqual(target.height, 960)
    XCTAssertEqual(target.width, 540)
  }

  func testThumbnailPathClampsAPastEndPositionToTheLastFrame() {
    // Mirrors the clamp Thumbnails.extractThumbnailJpeg applies before building the
    // requested CMTime, so a caller asking past the end still gets the last frame.
    XCTAssertEqual(MediaMath.clampPositionMs(9000, durationMs: 4000), 4000)
  }

  // MARK: - MediaMath.rotationDegrees(from:)

  func testRotationDegreesIdentityTransformIsZero() {
    XCTAssertEqual(MediaMath.rotationDegrees(from: .identity), 0)
  }

  func testRotationDegrees90DegreeClockwiseTransform() {
    // The shape of a real phone-portrait `preferredTransform`: rotates the coded landscape
    // frame 90 degrees clockwise for display.
    let transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1920, ty: 0)
    XCTAssertEqual(MediaMath.rotationDegrees(from: transform), 90)
  }

  func testRotationDegrees180DegreeTransform() {
    let transform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080)
    XCTAssertEqual(MediaMath.rotationDegrees(from: transform), 180)
  }

  func testRotationDegrees270DegreeTransform() {
    let transform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1080)
    XCTAssertEqual(MediaMath.rotationDegrees(from: transform), 270)
  }

  // MARK: - Arguments.requireReadableMediaFile

  func testRequireReadableMediaFileBlankPathRejectedAsUnsupportedInput() {
    XCTAssertThrowsError(try Arguments.requireReadableMediaFile("   ")) { error in
      XCTAssertEqual((error as? CompressVideoError)?.code, "unsupportedInput")
    }
  }

  func testRequireReadableMediaFileMissingFileRejectedAsFileNotFound() {
    XCTAssertThrowsError(
      try Arguments.requireReadableMediaFile(
        "/tmp/compress_video_arguments_test_does_not_exist_12345.mp4"
      )
    ) { error in
      XCTAssertEqual((error as? CompressVideoError)?.code, "fileNotFound")
    }
  }

  func testRequireReadableMediaFileEmptyFileRejectedAsUnsupportedInput() {
    let tempPath = NSTemporaryDirectory() + "compress_video_arguments_test_\(UUID().uuidString).mp4"
    FileManager.default.createFile(atPath: tempPath, contents: Data())
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    XCTAssertThrowsError(try Arguments.requireReadableMediaFile(tempPath)) { error in
      XCTAssertEqual((error as? CompressVideoError)?.code, "unsupportedInput")
    }
  }

  func testRequireReadableMediaFileRealFileReturnsAStandardisedPathAndDoesNotThrow() {
    let tempPath = NSTemporaryDirectory() + "compress_video_arguments_test_\(UUID().uuidString).mp4"
    FileManager.default.createFile(atPath: tempPath, contents: Data([1, 2, 3]))
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    XCTAssertNoThrow(try Arguments.requireReadableMediaFile(tempPath))
  }

  // MARK: - Arguments.requireWritableOutputParent

  func testRequireWritableOutputParentMissingParentDirectoryRejectedAsIo() {
    let missingDir =
      NSTemporaryDirectory() + "compress_video_arguments_test_missing_\(UUID().uuidString)"
    XCTAssertThrowsError(
      try Arguments.requireWritableOutputParent("\(missingDir)/thumb.jpg")
    ) { error in
      XCTAssertEqual((error as? CompressVideoError)?.code, "io")
    }
  }

  func testRequireWritableOutputParentExistingWritableParentDoesNotThrow() {
    XCTAssertNoThrow(
      try Arguments.requireWritableOutputParent(NSTemporaryDirectory() + "thumb.jpg")
    )
  }

  // MARK: - Arguments pure validators

  func testValidatePositionMsNegativeRejectedAsUnsupportedInput() {
    XCTAssertEqual(Arguments.validatePositionMs(-1), "unsupportedInput")
  }

  func testValidatePositionMsZeroOrPositiveIsValid() {
    XCTAssertNil(Arguments.validatePositionMs(0))
    XCTAssertNil(Arguments.validatePositionMs(1500))
  }

  func testValidateQualityBelowOneRejectedAsUnsupportedInput() {
    XCTAssertEqual(Arguments.validateQuality(0), "unsupportedInput")
  }

  func testValidateQualityAbove100RejectedAsUnsupportedInput() {
    XCTAssertEqual(Arguments.validateQuality(101), "unsupportedInput")
  }

  func testValidateQualityWithinRangeIsValid() {
    XCTAssertNil(Arguments.validateQuality(1))
    XCTAssertNil(Arguments.validateQuality(100))
  }

  func testValidateMaxDimensionPxNonPositiveRejectedAsUnsupportedInput() {
    XCTAssertEqual(Arguments.validateMaxDimensionPx(0), "unsupportedInput")
    XCTAssertEqual(Arguments.validateMaxDimensionPx(-100), "unsupportedInput")
  }

  func testValidateMaxDimensionPxNilOrPositiveIsValid() {
    XCTAssertNil(Arguments.validateMaxDimensionPx(nil))
    XCTAssertNil(Arguments.validateMaxDimensionPx(1))
  }

  func testValidateOutputPathBlankRejectedAsUnsupportedInput() {
    XCTAssertEqual(Arguments.validateOutputPath("   "), "unsupportedInput")
  }

  func testValidateOutputPathNilOrNonBlankIsValid() {
    XCTAssertNil(Arguments.validateOutputPath(nil))
    XCTAssertNil(Arguments.validateOutputPath("/tmp/thumb.jpg"))
  }

  // MARK: - Arguments.requireValidThumbnailArgs

  func testRequireValidThumbnailArgsAllValidDoesNotThrow() {
    XCTAssertNoThrow(
      try Arguments.requireValidThumbnailArgs(
        positionMs: 1500,
        quality: 80,
        maxDimensionPx: 1920,
        outputPath: "/tmp/thumb.jpg"
      )
    )
    XCTAssertNoThrow(
      try Arguments.requireValidThumbnailArgs(
        positionMs: 0,
        quality: 1,
        maxDimensionPx: nil,
        outputPath: nil
      )
    )
  }

  func testRequireValidThumbnailArgsNegativePositionMsThrowsWithThatReason() {
    XCTAssertThrowsError(
      try Arguments.requireValidThumbnailArgs(
        positionMs: -1,
        quality: 80,
        maxDimensionPx: nil,
        outputPath: nil
      )
    ) { error in
      XCTAssertEqual((error as? CompressVideoError)?.code, "unsupportedInput")
    }
  }

  func testRequireValidThumbnailArgsQualityOutOfRangeThrowsWithThatReason() {
    XCTAssertThrowsError(
      try Arguments.requireValidThumbnailArgs(
        positionMs: 0,
        quality: 0,
        maxDimensionPx: nil,
        outputPath: nil
      )
    ) { error in
      XCTAssertEqual((error as? CompressVideoError)?.code, "unsupportedInput")
    }
  }

  func testRequireValidThumbnailArgsNonPositiveMaxDimensionThrowsWithThatReason() {
    XCTAssertThrowsError(
      try Arguments.requireValidThumbnailArgs(
        positionMs: 0,
        quality: 80,
        maxDimensionPx: 0,
        outputPath: nil
      )
    ) { error in
      XCTAssertEqual((error as? CompressVideoError)?.code, "unsupportedInput")
    }
  }

  func testRequireValidThumbnailArgsBlankOutputPathThrowsWithThatReason() {
    XCTAssertThrowsError(
      try Arguments.requireValidThumbnailArgs(
        positionMs: 0,
        quality: 80,
        maxDimensionPx: nil,
        outputPath: "   "
      )
    ) { error in
      XCTAssertEqual((error as? CompressVideoError)?.code, "unsupportedInput")
    }
  }

  // MARK: - SizeGuard.resolve
  //
  // Numeric source of truth: android/src/test/kotlin/com/danjjohnson/compress_video/
  // SizeGuardTest.kt. One Swift `func test...` per Kotlin `@Test`, same input values, same
  // expected outputs, same Swift case count (41) as the Kotlin `@Test` count (41) -- proven by
  // counting both, not asserted. A disagreement here is a port bug in SizeGuard.swift, never a
  // reason to edit SizeGuard.kt or SizeGuardTest.kt (03-02-PLAN.md's prohibition).

  private func sizeGuardDefaultInput(
    displayedWidthPx: Int = 1080,
    displayedHeightPx: Int = 1920,
    rotationDegrees: Int = 90,
    durationMs: Int64 = 4000,
    sizeBytes: Int64 = 4_454_349,
    videoCodec: String = "h264",
    videoBitrateBps: Int64? = 8_764_164,
    frameRateFps: Double? = 60.0,
    hasAudio: Bool = true,
    audioCodec: String? = "aac",
    audioBitrateBps: Int64? = 128_000
  ) -> SizeGuard.InputInfo {
    SizeGuard.InputInfo(
      displayedWidthPx: displayedWidthPx,
      displayedHeightPx: displayedHeightPx,
      rotationDegrees: rotationDegrees,
      durationMs: durationMs,
      sizeBytes: sizeBytes,
      videoCodec: videoCodec,
      videoBitrateBps: videoBitrateBps,
      frameRateFps: frameRateFps,
      hasAudio: hasAudio,
      audioCodec: audioCodec,
      audioBitrateBps: audioBitrateBps
    )
  }

  private func sizeGuardDefaultOptions(
    maxLongSidePx: Int64? = nil,
    videoBitrateBps: Int64? = nil,
    targetSizeMb: Double? = nil,
    presetMaxLongSidePx: Int64 = 1280,
    presetVideoBitrateBps: Int64 = 2_500_000,
    maxFps: Int64 = 30,
    audioStripped: Bool = false,
    audioPassthroughRequested: Bool = true,
    requestedAudioBitrateBps: Int64? = nil,
    trimStartMs: Int64? = nil,
    trimEndMs: Int64? = nil
  ) -> SizeGuard.Options {
    SizeGuard.Options(
      maxLongSidePx: maxLongSidePx,
      videoBitrateBps: videoBitrateBps,
      targetSizeMb: targetSizeMb,
      presetMaxLongSidePx: presetMaxLongSidePx,
      presetVideoBitrateBps: presetVideoBitrateBps,
      maxFps: maxFps,
      audioStripped: audioStripped,
      audioPassthroughRequested: audioPassthroughRequested,
      requestedAudioBitrateBps: requestedAudioBitrateBps,
      trimStartMs: trimStartMs,
      trimEndMs: trimEndMs
    )
  }

  /// A qualifying baseline for `SizeGuard.Plan.wouldTransmux`: input long side exactly equal
  /// to the preset's own cap, frame rate exactly at the cap, H.264+AAC, and an input video
  /// bitrate comfortably inside the 1.15x headroom of the resolved (== preset, since
  /// longSideRatio/fpsRatio are both 1.0) 800,000bps target. Every transmux test below flips
  /// exactly one field off this baseline.
  private func sizeGuardTransmuxInput(
    displayedWidthPx: Int = 640,
    displayedHeightPx: Int = 360,
    rotationDegrees: Int = 0,
    durationMs: Int64 = 4000,
    sizeBytes: Int64 = 5_000_000,
    videoCodec: String = "h264",
    videoBitrateBps: Int64? = 800_000,
    frameRateFps: Double? = 30.0,
    hasAudio: Bool = true,
    audioCodec: String? = "aac",
    audioBitrateBps: Int64? = 128_000
  ) -> SizeGuard.InputInfo {
    SizeGuard.InputInfo(
      displayedWidthPx: displayedWidthPx,
      displayedHeightPx: displayedHeightPx,
      rotationDegrees: rotationDegrees,
      durationMs: durationMs,
      sizeBytes: sizeBytes,
      videoCodec: videoCodec,
      videoBitrateBps: videoBitrateBps,
      frameRateFps: frameRateFps,
      hasAudio: hasAudio,
      audioCodec: audioCodec,
      audioBitrateBps: audioBitrateBps
    )
  }

  private func sizeGuardTransmuxOptions(
    maxLongSidePx: Int64? = nil,
    videoBitrateBps: Int64? = nil,
    targetSizeMb: Double? = nil,
    presetMaxLongSidePx: Int64 = 640,
    presetVideoBitrateBps: Int64 = 800_000,
    maxFps: Int64 = 30,
    audioStripped: Bool = false,
    audioPassthroughRequested: Bool = true,
    requestedAudioBitrateBps: Int64? = nil,
    trimStartMs: Int64? = nil,
    trimEndMs: Int64? = nil
  ) -> SizeGuard.Options {
    SizeGuard.Options(
      maxLongSidePx: maxLongSidePx,
      videoBitrateBps: videoBitrateBps,
      targetSizeMb: targetSizeMb,
      presetMaxLongSidePx: presetMaxLongSidePx,
      presetVideoBitrateBps: presetVideoBitrateBps,
      maxFps: maxFps,
      audioStripped: audioStripped,
      audioPassthroughRequested: audioPassthroughRequested,
      requestedAudioBitrateBps: requestedAudioBitrateBps,
      trimStartMs: trimStartMs,
      trimEndMs: trimEndMs
    )
  }

  func testPresetAppliedToSourceLargerThanPresetLongSide_scalesDown() {
    let plan = SizeGuard.resolve(input: sizeGuardDefaultInput(), options: sizeGuardDefaultOptions())
    XCTAssertEqual(plan.targetWidthPx, 720)
    XCTAssertEqual(plan.targetHeightPx, 1280)
    XCTAssertEqual(plan.videoBitrateBps, 2_500_000)
  }

  func testPresetAppliedToSourceExactlyEqualToPresetLongSide_noChangeAndBitrateScaleFactorExactlyOne()
  {
    let input = sizeGuardDefaultInput(
      displayedWidthPx: 720, displayedHeightPx: 1280, frameRateFps: 30.0)
    let plan = SizeGuard.resolve(input: input, options: sizeGuardDefaultOptions())
    XCTAssertEqual(plan.targetWidthPx, 720)
    XCTAssertEqual(plan.targetHeightPx, 1280)
    XCTAssertEqual(plan.videoBitrateBps, 2_500_000)
  }

  func testPresetAppliedToSmallerSource_doesNotSpendTheFullPresetBitrate() {
    let input = sizeGuardDefaultInput(
      displayedWidthPx: 360, displayedHeightPx: 640, frameRateFps: 30.0)
    let plan = SizeGuard.resolve(input: input, options: sizeGuardDefaultOptions())
    // No upscale: the source is already below the preset's long side.
    XCTAssertEqual(plan.targetWidthPx, 360)
    XCTAssertEqual(plan.targetHeightPx, 640)
    // Bitrate scales down by the square of (640 / 1280) = 0.25, not left at 2,500,000.
    XCTAssertEqual(plan.videoBitrateBps, 625_000)
    XCTAssertTrue(plan.videoBitrateBps < sizeGuardDefaultOptions().presetVideoBitrateBps)
  }

  func testExplicitLongSideOverridesThePreset_whileThePresetBitrateFormulaStillApplies() {
    let input = sizeGuardDefaultInput(frameRateFps: 30.0)
    let options = sizeGuardDefaultOptions(maxLongSidePx: 960)
    let plan = SizeGuard.resolve(input: input, options: options)
    XCTAssertEqual(plan.targetHeightPx, 960)
    XCTAssertEqual(plan.targetWidthPx, 540)
    // Scaled by (960 / 1280)^2 = 0.5625 against the preset's own 2,500,000 -- the override
    // changed the target, not the preset's own reference bitrate.
    XCTAssertEqual(plan.videoBitrateBps, 1_406_250)
  }

  func testExplicitBitrateOverridesThePreset_whileThePresetLongSideStillApplies() {
    let input = sizeGuardDefaultInput(frameRateFps: 30.0)
    let options = sizeGuardDefaultOptions(videoBitrateBps: 1_200_000)
    let plan = SizeGuard.resolve(input: input, options: options)
    XCTAssertEqual(plan.targetHeightPx, 1280)
    XCTAssertEqual(plan.videoBitrateBps, 1_200_000)
  }

  func testTargetSizeMbProducesTheDocumentedFormulaBitrate() {
    let options = sizeGuardDefaultOptions(targetSizeMb: 2.0)
    let plan = SizeGuard.resolve(input: sizeGuardDefaultInput(), options: options)
    // (2.0 * 1e6 * 8 / 4.0) * 0.97 - 128000 = 3,880,000 - 128,000 = 3,752,000.
    XCTAssertEqual(plan.videoBitrateBps, 3_752_000)
    XCTAssertEqual(plan.audioBitrateBps, 128_000)
  }

  func testTargetSizeMbSoSmallThe200000FloorBinds() {
    let options = sizeGuardDefaultOptions(targetSizeMb: 0.0001)
    let plan = SizeGuard.resolve(input: sizeGuardDefaultInput(), options: options)
    XCTAssertEqual(plan.videoBitrateBps, 200_000)
  }

  func testTargetSizeMbSoLargeTheInputBitrateCapBinds() {
    let options = sizeGuardDefaultOptions(targetSizeMb: 100.0)
    let plan = SizeGuard.resolve(input: sizeGuardDefaultInput(), options: options)
    XCTAssertEqual(plan.videoBitrateBps, 8_764_164)
  }

  func testTargetSizeMbWithZeroDurationAndNoInputBitrate_fallsBackToFloorInsteadOfOverflowing() {
    let input = sizeGuardDefaultInput(durationMs: 0, videoBitrateBps: nil)
    let options = sizeGuardDefaultOptions(targetSizeMb: 2.0)
    let plan = SizeGuard.resolve(input: input, options: options)
    XCTAssertEqual(plan.videoBitrateBps, 200_000)
  }

  func testOddScalingCase_neitherOutputDimensionIsEverOdd() {
    let input = sizeGuardDefaultInput(displayedWidthPx: 853, displayedHeightPx: 1517)
    let options = sizeGuardDefaultOptions(maxLongSidePx: 641)
    let plan = SizeGuard.resolve(input: input, options: options)
    XCTAssertEqual(plan.targetWidthPx % 2, 0)
    XCTAssertEqual(plan.targetHeightPx % 2, 0)
    XCTAssertTrue(plan.targetHeightPx <= 641)
    XCTAssertTrue(plan.targetWidthPx <= 641)
  }

  func testMaxLongSidePxOfExactly16_acceptedAndTheShortSideFloorsAt16() {
    let input = sizeGuardDefaultInput(displayedWidthPx: 1920, displayedHeightPx: 100)
    let options = sizeGuardDefaultOptions(maxLongSidePx: 16)
    let plan = SizeGuard.resolve(input: input, options: options)
    XCTAssertEqual(plan.targetWidthPx, 16)
    // Naive scaling would give 100 * (16/1920) ~= 0.83, rounded down and evened to 0 -- the
    // 16px floor prevents a zero or sub-minimum short side reaching the encoder.
    XCTAssertEqual(plan.targetHeightPx, 16)
  }

  func testFps60InputAtMaxFps30_effectiveFpsIs30() {
    let plan = SizeGuard.resolve(input: sizeGuardDefaultInput(), options: sizeGuardDefaultOptions())
    XCTAssertEqual(plan.effectiveFps, 30)
  }

  func testFps30InputAtMaxFps60_effectiveFpsIs30NotUpscaled() {
    let input = sizeGuardDefaultInput(frameRateFps: 30.0)
    let options = sizeGuardDefaultOptions(maxFps: 60)
    let plan = SizeGuard.resolve(input: input, options: options)
    XCTAssertEqual(plan.effectiveFps, 30)
  }

  func testFps29p97InputAtMaxFps30_effectiveFpsIs30_provingHalfUpRounding() {
    let input = sizeGuardDefaultInput(frameRateFps: 29.97)
    let plan = SizeGuard.resolve(input: input, options: sizeGuardDefaultOptions())
    // A truncating (non-half-up) rounder would give 29, and min(30, 29) = 29 -- wrong.
    XCTAssertEqual(plan.effectiveFps, 30)
  }

  func testUnknownInputFrameRate_fallsBackToMaxFpsUnchanged() {
    let input = sizeGuardDefaultInput(frameRateFps: nil)
    let options = sizeGuardDefaultOptions(maxFps: 24)
    let plan = SizeGuard.resolve(input: input, options: options)
    XCTAssertEqual(plan.effectiveFps, 24)
  }

  func testUnknownInputVideoBitrate_noCapApplied_computedBitrateStands() {
    let input = sizeGuardDefaultInput(videoBitrateBps: nil, frameRateFps: 30.0)
    let plan = SizeGuard.resolve(input: input, options: sizeGuardDefaultOptions())
    XCTAssertEqual(plan.videoBitrateBps, 2_500_000)
  }

  func testStrippedAudio_bitrateZero_excludedFromTargetSizeSubtraction() {
    let options = sizeGuardDefaultOptions(targetSizeMb: 2.0, audioStripped: true)
    let plan = SizeGuard.resolve(input: sizeGuardDefaultInput(), options: options)
    XCTAssertEqual(plan.audioBitrateBps, 0)
    // No audio subtraction: (2.0 * 1e6 * 8 / 4.0) * 0.97 = 3,880,000, unlike the audio-present
    // case (3,752,000) proven in testTargetSizeMbProducesTheDocumentedFormulaBitrate.
    XCTAssertEqual(plan.videoBitrateBps, 3_880_000)
  }

  func testRequestedAudioBitrateInsideTheRange_passesThroughUnchanged() {
    let options = sizeGuardDefaultOptions(requestedAudioBitrateBps: 64_000)
    let plan = SizeGuard.resolve(input: sizeGuardDefaultInput(), options: options)
    XCTAssertEqual(plan.audioBitrateBps, 64_000)
  }

  func testNoRequestedAudioBitrate_fallsBackToTheSourceSOwnAudioBitrate() {
    // defaultInput's audioBitrateBps is 128000; requestedAudioBitrateBps is nil in
    // sizeGuardDefaultOptions(), so rule 5's fallback chain (request, then source, then the
    // 128,000bps project default) resolves to the source's own value here -- which happens to
    // equal the same project default, so this case also overrides the source value to
    // something else to prove the fallback is really reading the source, not coincidentally
    // landing on the same default either way.
    let input = sizeGuardDefaultInput(audioBitrateBps: 96_000)
    let plan = SizeGuard.resolve(input: input, options: sizeGuardDefaultOptions())
    XCTAssertEqual(plan.audioBitrateBps, 96_000)
  }

  func testRequestedAudioBitrateBelow8000_clampedUpToTheFloor() {
    let options = sizeGuardDefaultOptions(requestedAudioBitrateBps: 100)
    let plan = SizeGuard.resolve(input: sizeGuardDefaultInput(), options: options)
    XCTAssertEqual(plan.audioBitrateBps, 8_000)
  }

  func testRequestedAudioBitrateAbove960000_clampedDownToTheCeiling() {
    let options = sizeGuardDefaultOptions(requestedAudioBitrateBps: 2_000_000)
    let plan = SizeGuard.resolve(input: sizeGuardDefaultInput(), options: options)
    XCTAssertEqual(plan.audioBitrateBps, 960_000)
  }

  func testTrimmedRequest_usesTheTrimmedDurationForTargetSizeBitrateAndPredictedBytes() {
    let options = sizeGuardDefaultOptions(targetSizeMb: 1.0, trimStartMs: 1000, trimEndMs: 3000)
    let plan = SizeGuard.resolve(input: sizeGuardDefaultInput(), options: options)
    XCTAssertEqual(plan.outputDurationMs, 2000)
    // (1.0 * 1e6 * 8 / 2.0) * 0.97 - 128000 = 3,880,000 - 128,000 = 3,752,000.
    XCTAssertEqual(plan.videoBitrateBps, 3_752_000)
    // ((3,752,000 + 128,000) * 2.0 / 8) * 1.03 = 970,000 * 1.03 = 999,100.
    XCTAssertEqual(plan.predictedOutputBytes, 999_100)
  }

  func testResolve_isPure_twoDifferentOptionsAgainstTheSameInputDoNotContaminateEachOther() {
    let input = sizeGuardDefaultInput()
    let p360 = sizeGuardDefaultOptions(presetMaxLongSidePx: 640, presetVideoBitrateBps: 800_000)
    let p720 = sizeGuardDefaultOptions()

    let p360Plan = SizeGuard.resolve(input: input, options: p360)
    let p720Plan = SizeGuard.resolve(input: input, options: p720)

    XCTAssertEqual(p360Plan.targetHeightPx, 640)
    XCTAssertEqual(p360Plan.videoBitrateBps, 800_000)
    XCTAssertEqual(p720Plan.targetHeightPx, 1280)
    XCTAssertEqual(p720Plan.videoBitrateBps, 2_500_000)
  }

  // --- wouldUseOriginal ---
  //
  // sizeGuardDefaultInput()/sizeGuardDefaultOptions() (1080x1920, preset cap 1280) never
  // qualifies for transmux -- the preset's own long side is below the input's -- so these
  // cases isolate the never-larger predicate from the transmux one. targetSizeMb=1.0 against
  // the default 4-second/128kbps-audio baseline resolves to a known, exact
  // predictedOutputBytes of 999,100 (same arithmetic as
  // testTargetSizeMbProducesTheDocumentedFormulaBitrate, halved for a 1.0MB target instead of
  // 2.0MB), so sizeBytes is placed directly at, above, and below that boundary rather than
  // re-deriving the bitrate math per case.

  func testWouldUseOriginal_predictedOutputAboveInputSize_setsTheFlag() {
    let options = sizeGuardDefaultOptions(targetSizeMb: 1.0)
    let input = sizeGuardDefaultInput(sizeBytes: 999_099)
    let plan = SizeGuard.resolve(input: input, options: options)
    XCTAssertEqual(plan.predictedOutputBytes, 999_100)
    XCTAssertTrue(plan.wouldUseOriginal)
  }

  func testWouldUseOriginal_predictedOutputExactlyEqualToInputSize_setsTheFlag() {
    let options = sizeGuardDefaultOptions(targetSizeMb: 1.0)
    let input = sizeGuardDefaultInput(sizeBytes: 999_100)
    let plan = SizeGuard.resolve(input: input, options: options)
    XCTAssertTrue(plan.wouldUseOriginal, "equality counts as 'would not help'")
  }

  func testWouldUseOriginal_predictedOutputOneByteBelowInputSize_doesNotSetTheFlag() {
    let options = sizeGuardDefaultOptions(targetSizeMb: 1.0)
    let input = sizeGuardDefaultInput(sizeBytes: 999_101)
    let plan = SizeGuard.resolve(input: input, options: options)
    XCTAssertFalse(plan.wouldUseOriginal)
  }

  func testWouldUseOriginal_neverSetWhenThePlanIsARemux() {
    // The qualifying transmux baseline predicts output bytes exactly equal to the input's own
    // size (a remux copies the same samples) -- which would trip the equality rule above if
    // wouldTransmux did not take precedence. It must not.
    let plan = SizeGuard.resolve(
      input: sizeGuardTransmuxInput(), options: sizeGuardTransmuxOptions())
    XCTAssertTrue(plan.wouldTransmux)
    XCTAssertEqual(plan.predictedOutputBytes, sizeGuardTransmuxInput().sizeBytes)
    XCTAssertFalse(plan.wouldUseOriginal)
  }

  // --- wouldTransmux ---
  //
  // sizeGuardTransmuxInput()/sizeGuardTransmuxOptions() is a baseline every one of the seven
  // conditions satisfies. Each case below flips exactly one field off that baseline.

  func testWouldTransmux_qualifyingBaseline_isTrue() {
    let plan = SizeGuard.resolve(
      input: sizeGuardTransmuxInput(), options: sizeGuardTransmuxOptions())
    XCTAssertTrue(plan.wouldTransmux)
  }

  func testWouldTransmux_nonH264VideoCodec_disqualifies() {
    let input = sizeGuardTransmuxInput(videoCodec: "hevc")
    let plan = SizeGuard.resolve(input: input, options: sizeGuardTransmuxOptions())
    XCTAssertFalse(plan.wouldTransmux)
  }

  func testWouldTransmux_nonAacAudioCodec_disqualifies() {
    let input = sizeGuardTransmuxInput(audioCodec: "opus")
    let plan = SizeGuard.resolve(input: input, options: sizeGuardTransmuxOptions())
    XCTAssertFalse(plan.wouldTransmux)
  }

  func testWouldTransmux_forcedAudioReencode_disqualifies() {
    let options = sizeGuardTransmuxOptions(audioPassthroughRequested: false)
    let plan = SizeGuard.resolve(input: sizeGuardTransmuxInput(), options: options)
    XCTAssertFalse(plan.wouldTransmux)
  }

  func testWouldTransmux_audioStrip_disqualifies() {
    let options = sizeGuardTransmuxOptions(audioStripped: true, audioPassthroughRequested: false)
    let plan = SizeGuard.resolve(input: sizeGuardTransmuxInput(), options: options)
    XCTAssertFalse(plan.wouldTransmux)
  }

  func testWouldTransmux_trimRequested_disqualifies() {
    let options = sizeGuardTransmuxOptions(trimStartMs: 500)
    let plan = SizeGuard.resolve(input: sizeGuardTransmuxInput(), options: options)
    XCTAssertFalse(plan.wouldTransmux)
  }

  func testWouldTransmux_longSideOnePixelAboveTheTarget_disqualifies() {
    let input = sizeGuardTransmuxInput(displayedWidthPx: 641)
    let plan = SizeGuard.resolve(input: input, options: sizeGuardTransmuxOptions())
    XCTAssertFalse(plan.wouldTransmux)
  }

  func testWouldTransmux_frameRateOneAboveTheCap_disqualifies() {
    let input = sizeGuardTransmuxInput(frameRateFps: 31.0)
    let plan = SizeGuard.resolve(input: input, options: sizeGuardTransmuxOptions())
    XCTAssertFalse(plan.wouldTransmux)
  }

  func testWouldTransmux_bitrateExactlyAt1point15TimesTheTarget_qualifies() {
    // Resolved video bitrate stays 800,000 (min against a raised input bitrate that is still
    // above the preset-scaled value), so 920,000 is exactly the 1.15x boundary.
    let input = sizeGuardTransmuxInput(videoBitrateBps: 920_000)
    let plan = SizeGuard.resolve(input: input, options: sizeGuardTransmuxOptions())
    XCTAssertEqual(plan.videoBitrateBps, 800_000)
    XCTAssertTrue(plan.wouldTransmux)
  }

  func testWouldTransmux_bitrateOneBpsAboveTheHeadroom_disqualifies() {
    let input = sizeGuardTransmuxInput(videoBitrateBps: 920_001)
    let plan = SizeGuard.resolve(input: input, options: sizeGuardTransmuxOptions())
    XCTAssertEqual(plan.videoBitrateBps, 800_000)
    XCTAssertFalse(plan.wouldTransmux)
  }

  func testWouldTransmux_unknownInputBitrate_disqualifies() {
    let input = sizeGuardTransmuxInput(videoBitrateBps: nil)
    let plan = SizeGuard.resolve(input: input, options: sizeGuardTransmuxOptions())
    XCTAssertFalse(plan.wouldTransmux)
  }

  func testWouldTransmux_noAudioInputWithEverythingElseQualifying_qualifies() {
    let input = sizeGuardTransmuxInput(hasAudio: false, audioCodec: nil)
    let plan = SizeGuard.resolve(input: input, options: sizeGuardTransmuxOptions())
    XCTAssertTrue(plan.wouldTransmux)
  }

  // --- estimate()/compress() can never disagree ---
  //
  // Both paths resolve through the identical SizeGuard.resolve call -- there is no other
  // resolution path either could take. These tests express that guarantee directly at this
  // level: resolve has no shared mutable state, so calling it twice for the identical
  // InputInfo/Options a real estimate-then-compress call pair would build can never produce two
  // different Plans.

  func testResolve_calledTwiceForIdenticalScalingInputsAndOptions_producesEqualPlans() {
    let input = sizeGuardDefaultInput()
    let options = sizeGuardDefaultOptions()
    let estimatePlan = SizeGuard.resolve(input: input, options: options)
    let compressPlan = SizeGuard.resolve(input: input, options: options)
    XCTAssertEqual(estimatePlan, compressPlan)
  }

  func testResolve_calledTwiceForIdenticalTransmuxQualifyingInputsAndOptions_producesEqualPlans() {
    let input = sizeGuardTransmuxInput()
    let options = sizeGuardTransmuxOptions()
    let estimatePlan = SizeGuard.resolve(input: input, options: options)
    let compressPlan = SizeGuard.resolve(input: input, options: options)
    XCTAssertEqual(estimatePlan, compressPlan)
    XCTAssertTrue(estimatePlan.wouldTransmux)
  }

  // MARK: - ErrorMapping
  //
  // One case per AVError.Code ErrorMapping.swift maps, mirroring Android's
  // ErrorMappingTest.kt's table-driven style. `.decoderNotFound`/`.encoderNotFound`/
  // `.decoderTemporarilyUnavailable`/`.encoderTemporarilyUnavailable` are the R-03-verified
  // real case names (03-RESEARCH.md Pitfall 6) -- NOT the CONTEXT.md-prose
  // `.decoderNotAvailable`/`.encoderNotAvailable`, which do not exist.

  func testKnownAVErrorCodesHasExactlyElevenEntries() {
    // Fails the whole suite if a code is ever added to knownAVErrorCodes without a
    // corresponding case below -- mirrors ErrorMappingTest.kt's own acceptance criterion.
    XCTAssertEqual(ErrorMapping.knownAVErrorCodes.count, 11)
  }

  func testReasonForAVErrorDecoderNotFoundMapsToDecoderUnavailable() {
    XCTAssertEqual(ErrorMapping.reasonForAVError(.decoderNotFound), "decoderUnavailable")
  }

  func testReasonForAVErrorDecoderTemporarilyUnavailableMapsToDecoderUnavailable() {
    XCTAssertEqual(
      ErrorMapping.reasonForAVError(.decoderTemporarilyUnavailable), "decoderUnavailable")
  }

  func testReasonForAVErrorEncoderNotFoundMapsToEncoderUnavailable() {
    XCTAssertEqual(ErrorMapping.reasonForAVError(.encoderNotFound), "encoderUnavailable")
  }

  func testReasonForAVErrorEncoderTemporarilyUnavailableMapsToEncoderUnavailable() {
    XCTAssertEqual(
      ErrorMapping.reasonForAVError(.encoderTemporarilyUnavailable), "encoderUnavailable")
  }

  func testReasonForAVErrorDiskFullMapsToOutOfSpace() {
    XCTAssertEqual(ErrorMapping.reasonForAVError(.diskFull), "outOfSpace")
  }

  func testReasonForAVErrorFileFormatNotRecognizedMapsToUnsupportedInput() {
    XCTAssertEqual(ErrorMapping.reasonForAVError(.fileFormatNotRecognized), "unsupportedInput")
  }

  func testReasonForAVErrorFileFailedToParseMapsToUnsupportedInput() {
    XCTAssertEqual(ErrorMapping.reasonForAVError(.fileFailedToParse), "unsupportedInput")
  }

  func testReasonForAVErrorDecodeFailedMapsToUnsupportedInput() {
    XCTAssertEqual(ErrorMapping.reasonForAVError(.decodeFailed), "unsupportedInput")
  }

  func testReasonForAVErrorExportFailedMapsToIo() {
    XCTAssertEqual(ErrorMapping.reasonForAVError(.exportFailed), "io")
  }

  func testReasonForAVErrorSessionNotRunningMapsToIo() {
    XCTAssertEqual(ErrorMapping.reasonForAVError(.sessionNotRunning), "io")
  }

  func testReasonForAVErrorOutOfMemoryMapsToIo() {
    XCTAssertEqual(ErrorMapping.reasonForAVError(.outOfMemory), "io")
  }

  func testReasonForAVErrorUnmappedCodeMapsToUnknown() {
    // .unknown is a real AVError.Code case deliberately NOT in knownAVErrorCodes -- an
    // unrecognised code must fall through to "unknown", not crash or silently mismap.
    XCTAssertEqual(ErrorMapping.reasonForAVError(.unknown), "unknown")
  }

  func testReasonForNSErrorUnrelatedMessageMapsToIo() {
    let error = NSError(
      domain: "CompressVideoTestDomain", code: 42,
      userInfo: [NSLocalizedDescriptionKey: "some unrelated failure"])
    XCTAssertEqual(ErrorMapping.reasonForNSError(error), "io")
  }

  func testReasonForNSErrorNoSpaceMessageMapsToOutOfSpace() {
    let error = NSError(
      domain: "CompressVideoTestDomain", code: 28,
      userInfo: [NSLocalizedDescriptionKey: "write failed: no space left on device"])
    XCTAssertEqual(ErrorMapping.reasonForNSError(error), "outOfSpace")
  }

  func testMessageForNSErrorFoldsInDomainAndNumericCode() {
    let error = NSError(
      domain: "CompressVideoTestDomain", code: 1234,
      userInfo: [NSLocalizedDescriptionKey: "boom"])
    let message = ErrorMapping.messageForNSError(error)
    XCTAssertTrue(message.contains("1234"))
    XCTAssertTrue(message.contains("CompressVideoTestDomain"))
  }

  // MARK: - PluginFiles.sweep

  private func makeTempCacheDirForSweepTest() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "compress_video_pluginfiles_test_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  func testSweepDeletesAPlainFileInsideTheCacheDirectory() {
    let cacheDir = makeTempCacheDirForSweepTest()
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    let filePath = cacheDir.appendingPathComponent("stale.mp4")
    FileManager.default.createFile(atPath: filePath.path, contents: Data([1, 2, 3]))

    let deletedCount = PluginFiles.sweep(cacheDir: cacheDir, skipResolvedPaths: [])

    XCTAssertEqual(deletedCount, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: filePath.path))
  }

  func testSweepDoesNotRecurseIntoASubdirectory() {
    let cacheDir = makeTempCacheDirForSweepTest()
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    let subDir = cacheDir.appendingPathComponent("nested", isDirectory: true)
    try? FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
    let nestedFile = subDir.appendingPathComponent("survivor.mp4")
    FileManager.default.createFile(atPath: nestedFile.path, contents: Data([4, 5, 6]))

    let deletedCount = PluginFiles.sweep(cacheDir: cacheDir, skipResolvedPaths: [])

    // A non-empty subdirectory is skipped outright (never walked into to decide) -- proven by
    // both: nothing was counted as deleted, and the nested file is still there.
    XCTAssertEqual(deletedCount, 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: nestedFile.path))
  }

  func testSweepDoesNotDeleteAFileNamedInTheExclusionSet() {
    let cacheDir = makeTempCacheDirForSweepTest()
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    let livePath = cacheDir.appendingPathComponent("live-job.mp4")
    FileManager.default.createFile(atPath: livePath.path, contents: Data([1]))
    let resolvedLivePath = livePath.resolvingSymlinksInPath().path

    let deletedCount = PluginFiles.sweep(
      cacheDir: cacheDir, skipResolvedPaths: [resolvedLivePath])

    XCTAssertEqual(deletedCount, 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: livePath.path))
  }

  func testSweepDoesNotDeleteTheTargetOfASymlinkPointingOutsideTheCacheDirectory() {
    let cacheDir = makeTempCacheDirForSweepTest()
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    let outsideDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "compress_video_pluginfiles_test_outside_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outsideDir) }
    let outsideFile = outsideDir.appendingPathComponent("do-not-delete.mp4")
    FileManager.default.createFile(atPath: outsideFile.path, contents: Data([7, 8, 9]))

    let symlinkPath = cacheDir.appendingPathComponent("escape-link.mp4")
    try? FileManager.default.createSymbolicLink(at: symlinkPath, withDestinationURL: outsideFile)

    let deletedCount = PluginFiles.sweep(cacheDir: cacheDir, skipResolvedPaths: [])

    XCTAssertEqual(deletedCount, 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: outsideFile.path))
  }

  // MARK: - JobRegistry

  private func makeTempFileURLForJobRegistryTest() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "compress_video_jobregistry_test_\(UUID().uuidString).mp4")
  }

  func testJobRegistryRegisterThenFindReturnsTheJob() {
    let jobId = "jobregistry-\(UUID().uuidString)"
    let tempFile = makeTempFileURLForJobRegistryTest()
    JobRegistry.register(jobId: jobId, cancel: {}, tempFile: tempFile)
    defer { JobRegistry.remove(jobId: jobId) }

    let found = JobRegistry.find(jobId: jobId)
    XCTAssertNotNil(found)
    XCTAssertEqual(found?.tempFile, tempFile)
  }

  func testJobRegistryFindReturnsNilForAnUnknownJobId() {
    XCTAssertNil(JobRegistry.find(jobId: "jobregistry-unknown-\(UUID().uuidString)"))
  }

  func testJobRegistryCancelInvokesTheClosureExactlyOnce() {
    let jobId = "jobregistry-\(UUID().uuidString)"
    var invocationCount = 0
    JobRegistry.register(
      jobId: jobId, cancel: { invocationCount += 1 }, tempFile: makeTempFileURLForJobRegistryTest())

    JobRegistry.cancel(jobId: jobId)

    XCTAssertEqual(invocationCount, 1)
  }

  func testJobRegistryASecondCancelOfTheSameIdInvokesNothingAndDoesNotThrow() {
    let jobId = "jobregistry-\(UUID().uuidString)"
    var invocationCount = 0
    JobRegistry.register(
      jobId: jobId, cancel: { invocationCount += 1 }, tempFile: makeTempFileURLForJobRegistryTest())

    JobRegistry.cancel(jobId: jobId)
    JobRegistry.cancel(jobId: jobId)

    XCTAssertEqual(invocationCount, 1)
  }

  func testJobRegistryCancelOfAnUnknownIdIsASilentNoOp() {
    // Must not throw or crash -- there is nothing further to assert beyond "this line runs".
    JobRegistry.cancel(jobId: "jobregistry-unknown-\(UUID().uuidString)")
  }

  func testJobRegistryCancelAfterTheJobIsMarkedTerminalDoesNothing() {
    let jobId = "jobregistry-\(UUID().uuidString)"
    var invocationCount = 0
    JobRegistry.register(
      jobId: jobId, cancel: { invocationCount += 1 }, tempFile: makeTempFileURLForJobRegistryTest())
    defer { JobRegistry.remove(jobId: jobId) }

    JobRegistry.markTerminal(jobId: jobId)
    JobRegistry.cancel(jobId: jobId)

    XCTAssertEqual(invocationCount, 0)
    XCTAssertNotNil(
      JobRegistry.find(jobId: jobId),
      "an already-terminal job must remain registered until its own compress() call removes it, "
        + "not be forgotten by a no-op cancel()")
  }

  func testJobRegistryCancelAllInvokesEveryRegisteredClosureAndEmptiesTheRegistry() {
    let jobIdA = "jobregistry-\(UUID().uuidString)"
    let jobIdB = "jobregistry-\(UUID().uuidString)"
    var invokedA = false
    var invokedB = false
    JobRegistry.register(
      jobId: jobIdA, cancel: { invokedA = true }, tempFile: makeTempFileURLForJobRegistryTest())
    JobRegistry.register(
      jobId: jobIdB, cancel: { invokedB = true }, tempFile: makeTempFileURLForJobRegistryTest())

    JobRegistry.cancelAll()

    XCTAssertTrue(invokedA)
    XCTAssertTrue(invokedB)
    XCTAssertNil(JobRegistry.find(jobId: jobIdA))
    XCTAssertNil(JobRegistry.find(jobId: jobIdB))
  }

  func testJobRegistryLiveTempFilePathsContainsExactlyTheLiveJobsPaths() {
    let jobIdA = "jobregistry-\(UUID().uuidString)"
    let jobIdB = "jobregistry-\(UUID().uuidString)"
    let tempFileA = makeTempFileURLForJobRegistryTest()
    let tempFileB = makeTempFileURLForJobRegistryTest()
    JobRegistry.register(jobId: jobIdA, cancel: {}, tempFile: tempFileA)
    JobRegistry.register(jobId: jobIdB, cancel: {}, tempFile: tempFileB)
    defer {
      JobRegistry.remove(jobId: jobIdA)
      JobRegistry.remove(jobId: jobIdB)
    }

    let livePaths = JobRegistry.liveTempFilePaths()

    XCTAssertEqual(
      livePaths,
      Set([tempFileA.resolvingSymlinksInPath().path, tempFileB.resolvingSymlinksInPath().path]))
  }

}
