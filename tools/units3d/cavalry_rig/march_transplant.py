"""Transplant a re-keyed cavalry MARCH into the shipped cavalry.glb, nothing else (LOCO-CAV-MARCH,
owner ruling 2026-11-13).

    python3 tools/units3d/cavalry_rig/march_transplant.py SHIPPED.glb EDITED.glb

EDITED is march_reauthor.export_march's glTF of the rig (its MARCH is `cavalry_MARCH`, bones under
their Blender names). Unlike the archers' transplant the key TIMES change (16 -> 128 intervals over
the same length), so every MARCH channel gets new accessors appended to the BIN and its sampler
repointed. The channel set and the clip length must match the shipped clip; every original JSON table
and BIN byte, the other clips (the appended pivots included), meshes, skins and binds are kept.
"""
import importlib.util
import json
from pathlib import Path
import sys

import numpy as np

_spec = importlib.util.spec_from_file_location(  # the archers' GLB reader / writer (same module name)
    'archer_march_transplant', Path(__file__).resolve().parents[1] / 'archer_arp/march_transplant.py')
_archer = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_archer)
read, write, channels = _archer.read, _archer.write, _archer.channels

BONES = {'Head': 'head_h', 'R_Head': 'head'}  # install.py's renames
TOL = 1e-6


def _append(gl, binary, values, like):
    binary += b'\0' * (-len(binary) % 4)
    data = np.ascontiguousarray(values, '<f4').tobytes()
    gl['bufferViews'].append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': len(data)})
    binary += data
    new = {k: v for k, v in like.items() if k not in ('bufferView', 'byteOffset', 'min', 'max', 'count')}
    new.update({'bufferView': len(gl['bufferViews']) - 1, 'count': int(values.shape[0])})
    if values.shape[1] == 1:
        new.update({'min': [float(values.min())], 'max': [float(values.max())]})
    gl['accessors'].append(new)
    return len(gl['accessors']) - 1


def transplant(shipped, edited):
    gl, binary = read(shipped)
    egl, ebin = read(edited)
    mine = channels(gl, binary)
    theirs = {(BONES.get(n, n), p): v for (n, p), v in channels(egl, ebin, 'cavalry_MARCH').items()}
    etimes = max((v[1] for v in theirs.values()), key=len)
    for key, (s, t, v) in list(theirs.items()):  # the exporter keeps a constant channel as two keys
        if len(t) == 2 and np.abs(v[1] - v[0]).max() <= TOL:
            theirs[key] = (s, etimes, np.repeat(v[:1], len(etimes), axis=0))
    for key in set(mine) - set(theirs):  # the generator keys no scale; the shipped export sampled it at 1
        if key[1] == 'scale' and np.abs(mine[key][2] - 1.0).max() <= TOL:
            theirs[key] = (None, etimes, np.ones((etimes.shape[0], 3), np.float32))
    if set(mine) != set(theirs):
        raise ValueError('MARCH channel sets differ: %s' % sorted(set(mine) ^ set(theirs)))
    original_json = json.dumps(gl, sort_keys=True)
    original_bin = bytes(binary)
    times = {theirs[k][1].tobytes() for k in theirs}
    if len(times) != 1:
        raise ValueError('edited MARCH channels do not share one key time list')
    old_end = float(next(iter(mine.values()))[1][-1, 0])
    if abs(float(etimes[0, 0])) > TOL or abs(float(etimes[-1, 0]) - old_end) > TOL:
        raise ValueError('edited MARCH runs %s..%s, shipped 0..%s' % (etimes[0, 0], etimes[-1, 0], old_end))
    input_index = None
    for key in sorted(mine):
        sampler, _, values = mine[key]
        _, _, evalues = theirs[key]
        if evalues.shape[1] != values.shape[1]:
            raise ValueError(f'value width differs for {key}')
        if sampler.get('interpolation', 'LINEAR') != 'LINEAR':
            sampler['interpolation'] = 'LINEAR'
        if input_index is None:
            input_index = _append(gl, binary, etimes, gl['accessors'][sampler['input']])
        sampler['input'] = input_index
        sampler['output'] = _append(gl, binary, evalues, gl['accessors'][sampler['output']])
    gl['buffers'][0]['byteLength'] = len(binary) + (-len(binary) % 4)
    if bytes(binary[:len(original_bin)]) != original_bin:
        raise AssertionError('original BIN bytes changed')
    before = json.loads(original_json)
    for table in ('accessors', 'bufferViews'):
        if gl[table][:len(before[table])] != before[table]:
            raise AssertionError(table + ' prefix changed')
    for key in set(before) - {'accessors', 'bufferViews', 'buffers', 'animations'}:
        if gl[key] != before[key]:
            raise AssertionError(key + ' changed')
    for old, new in zip(before['animations'], gl['animations']):
        if old['name'] != 'MARCH' and old != new:
            raise AssertionError(old['name'] + ' changed')
    return write(gl, binary), len(mine), int(etimes.shape[0])


def main():
    shipped, edited = map(Path, sys.argv[1:3])
    data, n, keys = transplant(shipped.read_bytes(), edited.read_bytes())
    shipped.write_bytes(data)
    print('TRANSPLANTED', n, 'MARCH channels,', keys, 'keys each, into', shipped)


if __name__ == '__main__':
    main()
