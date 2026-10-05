"""The relief's sky occlusion (tools/map3d/bake_relief_ao.py): flat ground
sees the whole sky, a pit and a wall's foot see less, a summit sees it all;
and the built pack's relief_ao.png matches its woods.png texel grid."""
import os

import numpy as np
import pytest
from PIL import Image

import bake_relief_ao
from packs import default_pack, map3d_dir

BAKE = os.path.join(map3d_dir(default_pack()), "bake")


def test_flat_ground_sees_the_whole_sky():
    ao = bake_relief_ao.sky_seen(np.zeros((40, 40), np.float32), 40.0, 8, [40, 80, 160])
    assert np.allclose(ao, 1.0)


def test_a_pit_sees_less_than_its_rim_and_a_summit_sees_it_all():
    h = np.zeros((41, 41), np.float32)
    h[20, 20] = -200.0   # a pit 200 m deep
    h[5, 5] = 300.0      # a lone summit
    ao = bake_relief_ao.sky_seen(h, 40.0, 8, [40, 80, 160])
    assert ao[20, 20] < 0.4
    assert ao[5, 5] == pytest.approx(1.0)
    assert ao[20, 20] < ao[20, 30] <= 1.0


def test_the_foot_of_a_wall_is_darker_than_its_top():
    h = np.zeros((40, 40), np.float32)
    h[:, 20:] = 400.0    # a 400 m scarp facing west
    ao = bake_relief_ao.sky_seen(h, 40.0, 12, [40, 80, 160, 320])
    assert ao[20, 19] < ao[20, 5] - 0.1, "the scarp's foot is shaded"
    assert ao[20, 25] == pytest.approx(1.0), "its top sees the whole sky"


def test_the_blur_keeps_the_mean():
    rng = np.random.default_rng(1)
    img = rng.random((30, 30)).astype(np.float32)
    assert bake_relief_ao.blur(img, 1.0).mean() == pytest.approx(img.mean(), abs=0.01)


@pytest.mark.skipif(not os.path.exists(os.path.join(BAKE, "relief_ao.png")),
                    reason="no built pack (tools/map3d/build_pack.sh)")
def test_the_built_occlusion_lies_on_the_woods_grid():
    ao = Image.open(os.path.join(BAKE, "relief_ao.png"))
    woods = Image.open(os.path.join(BAKE, "woods.png"))
    assert ao.mode == "L"
    assert ao.size == woods.size
