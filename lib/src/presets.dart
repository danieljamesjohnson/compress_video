// Preset seeds for CompressOptions.preset.
//
// These four (maxLongSidePx, videoBitrateBps) pairs are SEEDS, not final constants: they were
// measured against the real corpus in plan 02-04 (confirmed monotonic on
// portrait_hibitrate_1080p60.mp4, no adjustment needed) and doc/PRESETS.md, generated from these
// values via tool/measure_presets.dart, is what the README publishes. Do not edit these numbers
// from memory or "gut feel" -- change them only after a corpus measurement run, and update
// doc/PRESETS.md in the same change.
import 'compress_options.dart' show CompressPreset;

/// A resolved preset target: the output's maximum long side and target video bitrate, both at
/// a nominal 30 fps.
class PresetSpec {
  /// Creates a [PresetSpec].
  const PresetSpec({
    required this.maxLongSidePx,
    required this.videoBitrateBps,
  });

  /// Cap on the output's longer displayed side, in pixels.
  final int maxLongSidePx;

  /// Target video bitrate, in bits per second, at a nominal 30 fps.
  final int videoBitrateBps;
}

/// Maps each [CompressPreset] to its resolved [PresetSpec].
///
/// `CompressVideo.compress` resolves the caller's chosen preset through this map into
/// `maxLongSidePx` and `videoBitrateBps` before the request ever crosses the platform channel
/// -- no preset enum crosses the channel itself.
const Map<CompressPreset, PresetSpec>
kPresetSpecs = <CompressPreset, PresetSpec>{
  CompressPreset.p360: PresetSpec(maxLongSidePx: 640, videoBitrateBps: 800000),
  CompressPreset.p480: PresetSpec(maxLongSidePx: 854, videoBitrateBps: 1200000),
  CompressPreset.p720: PresetSpec(
    maxLongSidePx: 1280,
    videoBitrateBps: 2500000,
  ),
  CompressPreset.p1080: PresetSpec(
    maxLongSidePx: 1920,
    videoBitrateBps: 5000000,
  ),
};
