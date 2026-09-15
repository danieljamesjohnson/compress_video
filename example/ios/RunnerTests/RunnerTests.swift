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

}
