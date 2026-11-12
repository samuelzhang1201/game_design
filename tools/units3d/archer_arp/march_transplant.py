"""Transplant edited MARCH channels into the shipped archers.glb, nothing else.

    python3 tools/units3d/archer_arp/march_transplant.py SHIPPED.glb EDITED.glb

EDITED is a glTF export of the re-authored game rig (archer_game_export.blend,
export.py's settings). Every MARCH channel whose output differs by more than
TOL gets a NEW accessor appended to the BIN and its sampler repointed; key
times must be identical. All other JSON tables, every other animation (the
appended pivots included) and every original BIN byte are kept, so meshes,
skins, binds, gear and the other clips cannot change (owner ruling 2026-11-11:
archer MARCH only).
"""
import json
from pathlib import Path
import struct
import sys

import numpy as np

TOL = 1e-6
WIDTH = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}


def read(data):
    magic, version, length = struct.unpack_from('<III', data)
    if (magic, version, length) != (0x46546C67, 2, len(data)):
        raise ValueError('invalid GLB header')
    size, kind = struct.unpack_from('<II', data, 12)
    gl = json.loads(data[20:20 + size])
    bin_size, bin_kind = struct.unpack_from('<II', data, 20 + size)
    if kind != 0x4E4F534A or bin_kind != 0x004E4942:
        raise ValueError('expected JSON then BIN chunks')
    return gl, bytearray(data[28 + size:28 + size + bin_size])


def write(gl, binary):
    text = json.dumps(gl, separators=(',', ':')).encode()
    text += b' ' * (-len(text) % 4)
    binary = bytes(binary) + b'\0' * (-len(binary) % 4)
    return (struct.pack('<III', 0x46546C67, 2, 28 + len(text) + len(binary))
            + struct.pack('<II', len(text), 0x4E4F534A) + text
            + struct.pack('<II', len(binary), 0x004E4942) + binary)


def accessor(gl, binary, index):
    a = gl['accessors'][index]
    view = gl['bufferViews'][a['bufferView']]
    if a['componentType'] != 5126 or view.get('byteStride'):
        raise ValueError('expected tightly packed float accessors')
    offset = view.get('byteOffset', 0) + a.get('byteOffset', 0)
    return np.frombuffer(bytes(binary), '<f4', a['count'] * WIDTH[a['type']], offset).reshape(a['count'], -1)


def channels(gl, binary, name='MARCH'):
    anim = next(a for a in gl['animations'] if a['name'] == name)
    out = {}
    for channel in anim['channels']:
        sampler = anim['samplers'][channel['sampler']]
        key = (gl['nodes'][channel['target']['node']]['name'], channel['target']['path'])
        out[key] = (sampler, accessor(gl, binary, sampler['input']), accessor(gl, binary, sampler['output']))
    return out


def transplant(shipped, edited):
    gl, binary = read(shipped)
    egl, ebin = read(edited)
    mine, theirs = channels(gl, binary), channels(egl, ebin)
    if set(mine) != set(theirs):
        raise ValueError('MARCH channel sets differ')
    original_json = json.dumps(gl, sort_keys=True)
    original_bin = bytes(binary)
    changed = []
    for key in sorted(mine):
        sampler, times, values = mine[key]
        _, etimes, evalues = theirs[key]
        if times.shape != etimes.shape or np.abs(times - etimes).max() > TOL:
            raise ValueError(f'key times differ for {key}')
        if values.shape != evalues.shape:
            raise ValueError(f'value shape differs for {key}')
        if np.abs(values - evalues).max() <= TOL:
            continue
        binary += b'\0' * (-len(binary) % 4)
        data = np.ascontiguousarray(evalues, '<f4').tobytes()
        gl['bufferViews'].append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': len(data)})
        binary += data
        old = gl['accessors'][sampler['output']]
        new = {k: v for k, v in old.items() if k not in ('bufferView', 'byteOffset', 'min', 'max')}
        new['bufferView'] = len(gl['bufferViews']) - 1
        gl['accessors'].append(new)
        sampler['output'] = len(gl['accessors']) - 1
        changed.append({'node': key[0], 'path': key[1], 'max_change': float(np.abs(values - evalues).max())})
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
    return write(gl, binary), changed


def main():
    shipped, edited = map(Path, sys.argv[1:3])
    data, changed = transplant(shipped.read_bytes(), edited.read_bytes())
    shipped.write_bytes(data)
    print(json.dumps(changed, indent=1))
    print('TRANSPLANTED', len(changed), 'MARCH channels into', shipped)


if __name__ == '__main__':
    main()
