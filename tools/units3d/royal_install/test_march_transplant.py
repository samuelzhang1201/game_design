"""Self-check for royal_install/march_transplant.py on a tiny synthetic GLB (no Godot, no assets).

    python3 tools/units3d/royal_install/test_march_transplant.py
"""
import importlib.util
import json
from pathlib import Path

import numpy as np

_spec = importlib.util.spec_from_file_location('royal_march_transplant', Path(__file__).with_name('march_transplant.py'))
T = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(T)


def _glb():
    """Two nodes; MARCH keys hoof rotation and leg translation at 0, .5, 1; STANDBY one key."""
    floats = [np.array([[0.0], [0.5], [1.0]]), np.array([[0, 0, 0, 1], [0, 0.6, 0, 0.8], [0, 0, 0, 1]]),
              np.array([[0, 0, 0], [0, 1, 0], [0, 0, 0]]), np.array([[0.0]]), np.array([[0, 0, 0, 1]])]
    binary, views, accessors = bytearray(), [], []
    kinds = ['SCALAR', 'VEC4', 'VEC3', 'SCALAR', 'VEC4']
    for values, kind in zip(floats, kinds):
        data = np.ascontiguousarray(values, '<f4').tobytes()
        views.append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': len(data)})
        accessors.append({'bufferView': len(views) - 1, 'componentType': 5126, 'count': len(values), 'type': kind})
        binary += data
    gl = {'asset': {'version': '2.0'}, 'nodes': [{'name': 'hoof'}, {'name': 'leg'}],
          'buffers': [{'byteLength': len(binary)}], 'bufferViews': views, 'accessors': accessors,
          'animations': [
              {'name': 'MARCH', 'samplers': [{'input': 0, 'output': 1, 'interpolation': 'LINEAR'},
                                             {'input': 0, 'output': 2, 'interpolation': 'LINEAR'}],
               'channels': [{'sampler': 0, 'target': {'node': 0, 'path': 'rotation'}},
                            {'sampler': 1, 'target': {'node': 1, 'path': 'translation'}}]},
              {'name': 'STANDBY', 'samplers': [{'input': 3, 'output': 4, 'interpolation': 'LINEAR'}],
               'channels': [{'sampler': 0, 'target': {'node': 0, 'path': 'rotation'}}]}]}
    return T.write(gl, binary)


def _keys(native_mid=(0, 0.6, 0, 0.8), seam=True):
    s = np.sqrt(0.5)
    return {'times': [0.0, 0.25, 0.5, 0.75, 1.0], 'bones': {'hoof': {
        'rotation': [[0, 0, 0, 1], [0, s, 0, s], [0, 1, 0, 0], [0, s, 0, s], [0, 0, 0, 1] if seam else [0, 0.6, 0, 0.8]],
        'native': [[0, 0, 0, 1], [0, 0.3, 0, 0.95], list(native_mid), [0, 0.3, 0, 0.95], [0, 0, 0, 1]]}}}


def demo():
    shipped = _glb()
    data, n, count, (checked, mismatched) = T.transplant(shipped, _keys())
    assert (n, count, checked, mismatched) == (1, 5, 2, []), (n, count, checked, mismatched)
    gl, binary = T.read(data)
    old_gl, old_bin = T.read(shipped)
    assert bytes(binary[:len(old_bin)]) == bytes(old_bin), 'original BIN bytes kept'
    march = T.channels(gl, binary)
    assert march[('hoof', 'rotation')][1].shape == (5, 1) and np.allclose(march[('hoof', 'rotation')][2][2], [0, 1, 0, 0])
    assert np.allclose(march[('leg', 'translation')][2], T.channels(old_gl, old_bin)[('leg', 'translation')][2]), 'other channels kept'
    assert gl['animations'][1] == old_gl['animations'][1], 'other clips kept'
    # Godot's native rows must be the GLB's own keys (here the key at .5 is not), and the seam must close.
    for bad, why in ((_keys(native_mid=(0, 0.8, 0, 0.6)), 'not the GLB rotations'), (_keys(seam=False), 'seam')):
        try:
            T.transplant(shipped, bad)
        except ValueError as error:
            assert why in str(error), error
        else:
            raise AssertionError('accepted ' + why)
    print('test_march_transplant: ok')


if __name__ == '__main__':
    demo()
