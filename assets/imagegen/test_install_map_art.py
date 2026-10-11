"""Plain-assert tests of install_map_art.py's pure image helpers (no pytest
here, same convention as tools/map3d/test_bake_world.py):
    python3 assets/imagegen/test_install_map_art.py
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



def test_alpha_box_is_the_piece_a_flood_left_standing():
    # a nine-slice piece is cropped tight to what the ground's flood left:
    # a 4x3 opaque block at (5, 2) in a 12x8 transparent image
    w, h = 12, 8
    px = bytearray(w * h * 4)
    for y in range(2, 5):
        for x in range(5, 9):
            px[(y * w + x) * 4 + 3] = 255
    assert ia.alpha_box(w, h, px) == (5, 2, 9, 5)
    assert ia.alpha_box(w, h, bytearray(w * h * 4)) == (0, 0, w, h), "nothing left: the whole render"


def test_a_shadow_on_the_ground_floods_with_it_but_the_piece_stands():
    # grey ground (160), a darker grey shadow strip (90) touching a brown piece
    w, h = 10, 4
    px = bytearray()
    for y in range(h):
        for x in range(w):
            px += bytes((100, 65, 40)) if 4 <= x <= 5 else bytes((90, 90, 90)) if x == 6 else bytes((160, 160, 160))
    plain = ia.flood_ground(w, h, 3, bytes(px))
    shaded = ia.flood_ground(w, h, 3, bytes(px), shadows=True)
    assert ia.alpha_box(w, h, plain) == (4, 0, 7, 4), "without: the shadow stays part of the piece"
    assert ia.alpha_box(w, h, shaded) == (4, 0, 6, 4), "with: only the brown piece stands"


def test_a_ground_that_lightens_toward_the_floor_is_grown_over_but_a_crisp_piece_stands():
    # a grey ground lightening 2 per row down to the floor, a cream sheet in the middle
    w, h = 12, 30
    px = bytearray()
    for y in range(h):
        for x in range(w):
            g = 150 + 2 * y
            px += bytes((236, 226, 200)) if 4 <= x <= 7 and 5 <= y <= 20 else bytes((g, g, g))
    box = ia.alpha_box(w, h, ia.grow_ground(w, h, 3, bytes(px)))
    assert box == (4, 5, 8, 21), box


def test_guarded_intersection_overlapping_boxes_intersect_as_normal():
    assert ia.guarded_intersection((2, 2, 10, 10), (5, 5, 12, 12), 20, 20) == (5, 5, 10, 10)


def test_guarded_intersection_falls_back_to_the_shadow_flood_box_when_the_two_do_not_overlap():
    # board art fix round finding #2: a future render where the shadow-aware
    # flood and the gradient-grow flood disagree could leave two valid but
    # non-overlapping boxes; crop_rgba would get a negative-size box and
    # raise, aborting the whole install_missive batch. The guard falls back
    # to the shadow-flood box (`a`) alone instead of crashing.
    a = (2, 2, 8, 8)
    b = (20, 20, 30, 30)  # does not overlap a at all
    assert ia.guarded_intersection(a, b, 40, 40) == a


def test_guarded_intersection_falls_back_to_the_whole_render_when_even_that_is_empty():
    a = (5, 5, 5, 5)  # degenerate: zero width and height
    b = (20, 20, 30, 30)
    assert ia.guarded_intersection(a, b, 40, 40) == (0, 0, 40, 40)



def test_a_trim_cell_narrows_the_crop_and_an_empty_one_keeps_it():
    assert ia.trim_box((10, 20, 110, 70), "0|0|0|15") == (10, 20, 110, 55)
    assert ia.trim_box((10, 20, 110, 70), "") == (10, 20, 110, 70)
    assert ia.trim_box((10, 20, 110, 70), "0|30|0|30") == (10, 20, 110, 70), "a trim that eats the piece is ignored"

if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print("ok", name)
