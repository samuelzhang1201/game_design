"""Plain-assert tests of install_map_art.py's pure image helpers (no pytest
here, same convention as tools/map3d/test_bake_world.py):
    python3 assets/flux/test_install_map_art.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import install_map_art as ia  # noqa: E402


def _solid(w, h, r, g, b, a=255):
    return bytearray([r, g, b, a] * (w * h))


def test_pad_to_aspect_keeps_the_target_ratio_uncropped():
    # fix round 1: a trimmed cut-out (e.g. the 384x288 envelope) must be
    # padded toward the TARGET's own aspect, not squared off first (which
    # composed two aspect changes and stretched a non-square target).
    # Integer pixel dimensions cannot always hit the ratio exactly — the
    # tolerance here is one pixel's worth of rounding on a small 40px image;
    # a real (hundreds-of-px) cut-out rounds far closer than this.
    px = _solid(40, 40, 200, 0, 0)
    cw, chh, canvas = ia.pad_to_aspect(40, 40, px, 384 / 288)
    assert abs(cw / chh - 384 / 288) < 0.03, (cw, chh)
    assert cw >= 40 and chh >= 40
    # the original 40x40 block is centred, untouched (not stretched)
    ox, oy = (cw - 40) // 2, (chh - 40) // 2
    i = ((oy + 20) * cw + (ox + 20)) * 4
    assert canvas[i:i + 4] == bytearray([200, 0, 0, 255])


def test_pad_to_aspect_a_square_crop_toward_a_square_target_matches_pad_square():
    # the 48x48 pin target is square, so pad_to_aspect(..., 1.0) must behave
    # exactly like the existing pad_square (kept unchanged) for that case.
    px = _solid(30, 20, 5, 6, 7)
    side = max(30, 20)
    want = ia.pad_square(30, 20, px, side)
    cw, chh, got = ia.pad_to_aspect(30, 20, px, 1.0)
    assert (cw, chh) == (side, side)
    assert got == want


def test_pad_to_aspect_then_resize_does_not_distort_a_non_square_target():
    # Resizing the aspect-padded canvas straight to the target size must not
    # squash the cut-out: the padded canvas's own aspect already equals the
    # target's, so the resize is a uniform scale, never a stretch.
    tw, th = 384, 288
    px = _solid(40, 40, 10, 20, 30)
    cw, chh, canvas = ia.pad_to_aspect(40, 40, px, tw / th)
    small = ia.resize_rgba(cw, chh, canvas, tw, th)
    assert len(small) == tw * th * 4
    assert abs(cw / chh - tw / th) < 0.03


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print("ok", name)
