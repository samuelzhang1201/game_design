"""The tunic mask (no Blender): class 1 of the body's authored classes, laid on the atlas."""
import struct
import unittest
import zlib

import numpy as np

import tunic_mask as tm


class TunicMask(unittest.TestCase):
    def test_tunic_mask_matches_the_atlas(self):
        # 16x16 authored classes, rows top-down: [[1 2] [3 1]] in 8 px blocks
        cls = np.kron(np.array([[1, 2], [3, 1]]), np.ones((8, 8), int))
        mask = tm.tunic_mask_tiles(cls, [(0, 0, 32, 32), (32, 32, 32, 32)], 64)
        self.assertEqual(mask.shape, (64, 64))
        for x, y in ((0, 0), (32, 32)):
            tile = mask[y:y + 32, x:x + 32]           # rows bottom-up: the class map's top is high y
            self.assertGreaterEqual(tile[19:29, 3:13].min(), 0.99)   # class 1, top left
            self.assertGreaterEqual(tile[3:13, 19:29].min(), 0.99)   # class 1, bottom right
            self.assertLessEqual(tile[19:29, 19:29].max(), 0.01)     # class 2, top right
            self.assertLessEqual(tile[3:13, 3:13].max(), 0.01)       # class 3, bottom left
            self.assertTrue(0.01 < tile[24, 16] < 0.99)              # a softened edge
        self.assertEqual(mask[0:32, 32:64].max(), 0.0)              # outside the tiles
        self.assertEqual(mask[32:64, 0:32].max(), 0.0)

    def test_png_rows_run_top_down(self):
        a = np.zeros((2, 3), np.float32)
        a[1, :] = 1.0                                  # bottom-up: row 1 is the TOP of the image
        data = tm.png_gray(a)
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        w, h, depth, colour = struct.unpack(">IIBB", data[16:26])
        self.assertEqual((w, h, depth, colour), (3, 2, 8, 0))
        idat = data.index(b"IDAT")
        n = struct.unpack(">I", data[idat - 4:idat])[0]
        raw = zlib.decompress(data[idat + 4:idat + 4 + n])
        self.assertEqual(raw, b"\x00\xff\xff\xff\x00\x00\x00\x00")


if __name__ == "__main__":
    unittest.main()
