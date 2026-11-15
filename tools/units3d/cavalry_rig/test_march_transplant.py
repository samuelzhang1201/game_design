"""Hand-made GLBs for the cavalry MARCH transplant (no Blender, no Godot):
    python3 -m pytest tools/units3d/cavalry_rig/test_march_transplant.py"""
import sys
from pathlib import Path
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import march_transplant as mt  # noqa: E402


def glb(name, march, pivot, times):
    """Nodes Head (renamed head_h when installed) and Lance; clip `name` keys Head rotation, Lance
    translation and, for the shipped side, Lance scale; PIVOT_LEFT keys Head rotation."""
    arrays = [np.array(times, '<f4').reshape(-1, 1), np.array(march[0], '<f4'), np.array(march[1], '<f4'),
              np.array(pivot, '<f4'), np.array([[0.0], [1.0]], '<f4')]
    if len(march) > 2:
        arrays.append(np.array(march[2], '<f4'))
    arrays.append(np.array([times[0], times[-1]], '<f4').reshape(-1, 1))  # a two-key channel's times
    binary, views, accessors = b'', [], []
    for array in arrays:
        views.append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': array.nbytes})
        accessors.append({'bufferView': len(views) - 1, 'componentType': 5126, 'count': len(array),
                          'type': {1: 'SCALAR', 3: 'VEC3', 4: 'VEC4'}[array.shape[1]]})
        binary += array.tobytes()
    samplers = [{'input': 0, 'output': 1}, {'input': 0 if len(march[1]) == len(times) else len(arrays) - 1, 'output': 2}]
    channels = [{'sampler': 0, 'target': {'node': 0, 'path': 'rotation'}},
                {'sampler': 1, 'target': {'node': 1, 'path': 'translation'}}]
    if len(march) > 2:
        samplers.append({'input': 0, 'output': 5})
        channels.append({'sampler': 2, 'target': {'node': 1, 'path': 'scale'}})
    gl = {'asset': {'version': '2.0'}, 'nodes': [{'name': 'head_h' if name == 'MARCH' else 'Head'}, {'name': 'Lance'}],
          'buffers': [{'byteLength': len(binary)}], 'bufferViews': views, 'accessors': accessors,
          'animations': [{'name': name, 'samplers': samplers, 'channels': channels},
                         {'name': 'PIVOT_LEFT', 'samplers': [{'input': 4, 'output': 3}],
                          'channels': [{'sampler': 0, 'target': {'node': 0, 'path': 'rotation'}}]}]}
    return mt.write(gl, binary)


Q = [0, 0, 0, 1]
SHIPPED = glb('MARCH', ([Q, Q], [[0, 0, 0], [0, 1, 0]], [[1, 1, 1], [1, 1, 1]]), [Q, Q], (0.0, 0.5))
# three keys over the same 0.5 s; Lance translation constant (the exporter keeps it as two keys)
EDITED = glb('cavalry_MARCH', ([Q, [0, 0, .6, .8], Q], [[0, 2, 0], [0, 2, 0]]), [[1, 0, 0, 0]] * 2, (0.0, 0.25, 0.5))


class Transplant(unittest.TestCase):
    def test_march_is_rekeyed_and_nothing_else_moves(self):
        data, n, keys = mt.transplant(SHIPPED, EDITED)
        self.assertEqual((n, keys), (3, 3))
        gl, binary = mt.read(data)
        old, old_bin = mt.read(SHIPPED)
        self.assertEqual(bytes(binary[:len(old_bin)]), bytes(old_bin))
        self.assertEqual(gl['accessors'][:len(old['accessors'])], old['accessors'])
        self.assertEqual(gl['animations'][1], old['animations'][1])  # PIVOT_LEFT untouched
        march = mt.channels(gl, binary)
        np.testing.assert_allclose(march[('head_h', 'rotation')][1][:, 0], [0, .25, .5])
        np.testing.assert_allclose(march[('head_h', 'rotation')][2], [Q, [0, 0, .6, .8], Q], atol=1e-7)
        np.testing.assert_allclose(march[('Lance', 'translation')][2], [[0, 2, 0]] * 3)  # constant, expanded
        np.testing.assert_allclose(march[('Lance', 'scale')][2], [[1, 1, 1]] * 3)  # unit scale, re-keyed
        self.assertEqual(gl['buffers'][0]['byteLength'], len(binary))

    def test_a_different_length_or_channel_set_is_refused(self):
        with self.assertRaises(ValueError):
            mt.transplant(SHIPPED, glb('cavalry_MARCH', ([Q, Q], [[0, 2, 0], [0, 2, 0]]), [Q, Q], (0.0, 0.6)))
        with self.assertRaises(ValueError):  # a moving channel the shipped clip lacks
            mt.transplant(glb('MARCH', ([Q, Q], [[0, 0, 0], [0, 1, 0]]), [Q, Q], (0.0, 0.5)),
                          glb('cavalry_MARCH', ([Q, Q], [[0, 0, 0], [0, 1, 0]], [[1, 1, 1], [2, 2, 2]]),
                              [Q, Q], (0.0, 0.5)))


if __name__ == '__main__':
    unittest.main()
