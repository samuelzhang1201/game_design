"""pack_aerial.py's picture operations (pure numpy, no files)."""
import numpy as np

import pack_aerial


def test_tint_greys_turns_only_grey_pixels_and_keeps_their_light():
    a = np.zeros((1, 2, 3), np.float32)
    a[0, 0] = (0.5, 0.5, 0.5)       # grey stone
    a[0, 1] = (0.6, 0.5, 0.1)       # golden grass: chroma 0.5
    out = pack_aerial.tint_greys(a, "#C0A080", 1.0)
    w3 = np.array([0.2126, 0.7152, 0.0722], np.float32)
    assert out[0, 0, 0] > out[0, 0, 2]                       # the stone turned warm
    assert abs(float(out[0, 0] @ w3) - 0.5) < 1e-3           # at its own light
    assert np.allclose(out[0, 1], a[0, 1])                   # the grass untouched


def test_tint_greys_lift_lightens_the_stone():
    a = np.full((1, 1, 3), 0.4, np.float32)
    w3 = np.array([0.2126, 0.7152, 0.0722], np.float32)
    out = pack_aerial.tint_greys(a, "#C0A080", 1.0, lift=0.25)
    assert abs(float(out[0, 0] @ w3) - 0.5) < 1e-3
