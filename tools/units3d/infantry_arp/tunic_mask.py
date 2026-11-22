"""The infantry's tunic mask (no Blender): class 1 (green leather) of the body's authored material
classes (`textures/body_class.npy`), laid on the game atlas where the body sits, edges softened as
the atlas's own class passes are. The map's realm tint reads it (`unit_realm_tint.gdshader`)."""
import struct
import zlib

import numpy as np

TUNIC = 1


def box(a, r):
    """Box blur of radius r px over the first two axes (edges clamped)."""
    for axis in (0, 1):
        pad = [(0, 0)] * a.ndim
        pad[axis] = (r + 1, r)
        c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis)
        hi = np.take(c, range(2 * r + 1, c.shape[axis]), axis=axis)
        lo = np.take(c, range(0, c.shape[axis] - 2 * r - 1), axis=axis)
        a = (hi - lo) / (2 * r + 1)
    return a


def class_mask(cls, w, h, k):
    """Class `k` of `cls` (rows top-down, as authored) resampled to w x h, rows bottom-up as
    Blender's pixels, edges softened."""
    cls = cls[::-1]
    ys = (np.arange(h) * cls.shape[0]) // h
    xs = (np.arange(w) * cls.shape[1]) // w
    return box((cls[ys][:, xs] == k).astype(np.float32), 2)


def tunic_mask_tiles(cls, layout, size):
    """A size x size mask (rows bottom-up): the tunic class of `cls` in each (x, y, w, h) atlas
    rect of `layout`, 0 elsewhere."""
    out = np.zeros((size, size), np.float32)
    for x, y, w, h in layout:
        out[y:y + h, x:x + w] = class_mask(cls, w, h, TUNIC)
    return out


def png_gray(a):
    """8-bit greyscale PNG bytes of `a` (values 0..1, rows bottom-up)."""
    px = np.clip(np.rint(a[::-1] * 255), 0, 255).astype(np.uint8)
    raw = b"".join(b"\x00" + row.tobytes() for row in px)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    head = struct.pack(">IIBBBBB", px.shape[1], px.shape[0], 8, 0, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", head) + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))
