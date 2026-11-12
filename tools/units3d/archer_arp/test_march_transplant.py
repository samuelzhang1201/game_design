"""Hand-made GLBs for the MARCH transplant (no Blender, no Godot)."""
import json
import unittest

import numpy as np

import march_transplant as mt


def glb(march_toe, pivot_toe, times=(0.0, 1.0)):
    """Two nodes, MARCH (toe rotation + hip translation) and PIVOT_LEFT (toe)."""
    arrays = [np.array(times, '<f4'), np.array(march_toe, '<f4'), np.array([[0, 0, 0], [0, 1, 0]], '<f4'),
              np.array(pivot_toe, '<f4')]
    binary, views, accessors = b'', [], []
    for array, kind in zip(arrays, ['SCALAR', 'VEC4', 'VEC3', 'VEC4']):
        views.append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': array.nbytes})
        accessors.append({'bufferView': len(views) - 1, 'componentType': 5126, 'count': len(array), 'type': kind})
        binary += array.tobytes()
    gl = {'asset': {'version': '2.0'}, 'nodes': [{'name': 'toes_01.r'}, {'name': 'root.x'}],
          'buffers': [{'byteLength': len(binary)}], 'bufferViews': views, 'accessors': accessors,
          'animations': [
              {'name': 'MARCH', 'samplers': [{'input': 0, 'output': 1}, {'input': 0, 'output': 2}],
               'channels': [{'sampler': 0, 'target': {'node': 0, 'path': 'rotation'}},
                            {'sampler': 1, 'target': {'node': 1, 'path': 'translation'}}]},
              {'name': 'PIVOT_LEFT', 'samplers': [{'input': 0, 'output': 3}],
               'channels': [{'sampler': 0, 'target': {'node': 0, 'path': 'rotation'}}]}]}
    return mt.write(gl, binary)


IDENTITY = [[0, 0, 0, 1], [0, 0, 0, 1]]
LIFTED = [[0, 0, 0, 1], [-.29552, 0, 0, .95534]]  # 0.6 rad about -X at the second key


class Transplant(unittest.TestCase):
    def test_only_the_edited_channel_moves(self):
        shipped = glb(IDENTITY, IDENTITY)
        edited = glb(LIFTED, [[1, 0, 0, 0], [1, 0, 0, 0]])  # a different PIVOT must be ignored
        data, changed = mt.transplant(shipped, edited)
        self.assertEqual([(c['node'], c['path']) for c in changed], [('toes_01.r', 'rotation')])
        self.assertAlmostEqual(changed[0]['max_change'], .29552, places=6)  # the x component: 0 -> -.29552
        gl, binary = mt.read(data)
        old, old_bin = mt.read(shipped)
        self.assertEqual(bytes(binary[:len(old_bin)]), bytes(old_bin))  # every original byte kept
        self.assertEqual(gl['accessors'][:4], old['accessors'])
        self.assertEqual(gl['animations'][1], old['animations'][1])  # PIVOT_LEFT untouched
        march = mt.channels(gl, binary)
        np.testing.assert_allclose(march[('toes_01.r', 'rotation')][2], LIFTED, atol=0)
        np.testing.assert_allclose(march[('root.x', 'translation')][2], [[0, 0, 0], [0, 1, 0]], atol=0)
        np.testing.assert_allclose(mt.channels(gl, binary, 'PIVOT_LEFT')[(('toes_01.r', 'rotation'))][2], IDENTITY)
        self.assertEqual(gl['buffers'][0]['byteLength'], len(binary))

    def test_no_change_is_a_no_op_and_time_changes_reject(self):
        shipped = glb(IDENTITY, IDENTITY)
        data, changed = mt.transplant(shipped, glb(IDENTITY, IDENTITY))
        self.assertEqual(changed, [])
        self.assertEqual(json.loads(data[20:20 + int.from_bytes(data[12:16], 'little')])['accessors'],
                         mt.read(shipped)[0]['accessors'])
        with self.assertRaises(ValueError):
            mt.transplant(shipped, glb(LIFTED, IDENTITY, times=(0.0, 2.0)))


if __name__ == '__main__':
    unittest.main()
