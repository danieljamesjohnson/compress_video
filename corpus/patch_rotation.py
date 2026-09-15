#!/usr/bin/env python3
"""Patch the `tkhd` display-matrix in an MP4 so it carries a real rotation, the
way an iPhone (or any phone) writes portrait video: frames stay encoded
landscape, and the player rotates on decode using the matrix in `tkhd`.

Why this exists: `ffmpeg -metadata:s:v:0 rotate=90` is a documented, verified
no-op on the ffmpeg 6.1.1-3ubuntu5 build installed on danserver — it prints a
deprecation notice ("Conversion of a 'rotate' metadata key to a proper display
matrix rotation is deprecated...") but leaves the `tkhd` matrix at identity.
See `.planning/phases/01-typed-contract-ci-and-media-info/01-RESEARCH.md`
-> "Common Pitfalls" #1 and #2, and -> "Code Examples" (this function is a
transcription of the verified-working snippet from that research).

Box format is public: ISO/IEC 14496-12 (`tkhd` box, `matrix` field is 9 signed
32-bit fixed-point integers immediately before `width`/`height`).

Only 0 and 90 degrees clockwise are implemented/verified — that is all this
corpus needs.
"""
from __future__ import annotations

import struct
import sys


def find_tkhd_matrix_offset(data: bytearray, start: int = 0, end: int | None = None) -> int | None:
    """Recurse into moov/trak/mdia/udta looking for a `tkhd` box, and return the
    byte offset of the 36-byte matrix field within it (the matrix sits
    immediately before the trailing width/height fields of `tkhd`)."""
    end = end if end is not None else len(data)
    i = start
    while i < end - 8:
        size = struct.unpack(">I", data[i:i + 4])[0]
        boxtype = data[i + 4:i + 8]
        if size < 8:
            break
        if boxtype == b"tkhd":
            body_off = i + 8
            # matrix is the 36 bytes immediately before the trailing 8 bytes
            # of width/height (each a 32-bit fixed-point value).
            return body_off + (size - 8 - 8 - 36)
        if boxtype in (b"moov", b"trak", b"mdia", b"udta"):
            found = find_tkhd_matrix_offset(data, i + 8, i + size)
            if found is not None:
                return found
        i += size
    return None


def patch_rotation(path: str, height: int, degrees_cw: int = 90) -> None:
    """Rewrite the `tkhd` display matrix of the MP4 at `path` in place.

    `height` is the coded (pre-rotation) video height, used to build the
    fixed-point matrix per ISO/IEC 14496-12. Raises `RuntimeError` if no
    `tkhd` box is found (never silently exits 0 on a malformed/missing box).
    """
    with open(path, "rb") as f:
        data = bytearray(f.read())

    off = find_tkhd_matrix_offset(data)
    if off is None:
        raise RuntimeError(f"tkhd box not found in {path}")

    if degrees_cw == 90:
        # Verified this session: ffprobe then reports
        # side_data_list: [{"side_data_type": "Display Matrix", "rotation": -90}]
        # (ffprobe's rotation is signed/counter-clockwise; this is a 90-degree
        # *clockwise* phone-portrait rotation, matching real iPhone output).
        vals = (0, 0x10000, 0, -0x10000, 0, 0, height << 16, 0, 0x40000000)
    elif degrees_cw == 0:
        vals = (0x10000, 0, 0, 0, 0x10000, 0, 0, 0, 0x40000000)  # identity
    else:
        raise NotImplementedError("only 0/90 degrees clockwise are derived and verified")

    data[off:off + 36] = struct.pack(">9i", *vals)
    with open(path, "wb") as f:
        f.write(data)


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print(f"usage: {argv[0]} <path> <height> <degrees_cw>", file=sys.stderr)
        return 2
    path, height_str, degrees_str = argv[1], argv[2], argv[3]
    try:
        patch_rotation(path, int(height_str), int(degrees_str))
    except (RuntimeError, NotImplementedError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(f"patched {path}: {degrees_str} degrees clockwise (height={height_str})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
