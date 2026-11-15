"""Transplant the re-keyed royal MARCH hoof chains into the shipped royal.glb, nothing else
(LOCO-ROY-MARCH, owner ruling R-J 2026-11-13).

    python3 tools/units3d/royal_install/march_transplant.py SHIPPED.glb KEYS.json

KEYS.json is march_reauthor.gd's output: for each hoof-chain bone its local rotation at KEYS + 1
evenly spaced times over the clip (the last equal to the first), and the native rotation Godot
sampled at the same times. The shipped MARCH's own last key is NOT its first (a 2.3 mm loop seam);
the re-keyed chains close it. Before writing, the native rows at the shipped clip's own key times
must equal the GLB's keys (so a Godot bone local IS the glTF node rotation). Only those bones'
MARCH rotation channels get new accessors appended to the BIN (one shared time input) and their
samplers repointed, LINEAR; every original JSON table and BIN byte, every other MARCH channel,
the other clips (the appended pivots included), meshes, skins and binds are kept.
"""
import importlib.util
import json
from pathlib import Path
import sys

import numpy as np

_spec = importlib.util.spec_from_file_location(  # the archers' GLB reader / writer
    'archer_march_transplant', Path(__file__).resolve().parents[1] / 'archer_arp/march_transplant.py')
_archer = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_archer)
read, write, channels = _archer.read, _archer.write, _archer.channels

TOL = 1e-5


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


def _sampled(times, values, interpolation, at):
    """The shipped channel at time `at` (LINEAR: normalized lerp is enough at a key; STEP: hold)."""
    i = int(np.searchsorted(times, at + 1e-7, side='right') - 1)
    i = max(0, min(i, len(times) - 1))
    if interpolation == 'STEP' or i == len(times) - 1 or abs(times[i] - at) <= 1e-6:
        return values[i]
    raise ValueError(f'{at} is not a shipped key time')


def transplant(shipped, keys):
    gl, binary = read(shipped)
    mine = channels(gl, binary)
    times = np.array(keys['times'], dtype=np.float64)
    end = float(next(iter(mine.values()))[1][-1, 0])
    if abs(times[0]) > TOL or abs(times[-1] - end) > TOL:
        raise ValueError(f'keyed MARCH runs {times[0]}..{times[-1]}, shipped 0..{end}')
    # A Godot bone local is the glTF node rotation: check at every shipped key time.
    checked, mismatched = 0, []
    for name, rows in keys['bones'].items():
        sampler, t, v = mine[(name, 'rotation')]
        native = np.array(rows['native'])
        for k, at in enumerate(times[:-1]):  # the last row is the first again (the seam), by design
            if np.min(np.abs(t[:, 0] - at)) > 1e-6:
                continue
            q = _sampled(t[:, 0], v, sampler.get('interpolation', 'LINEAR'), at)
            checked += 1
            if min(np.abs(native[k] - q).max(), np.abs(native[k] + q).max()) > TOL:
                mismatched.append((name, round(float(at), 4)))
    # Godot's import moves a few keys (up to ~6 degrees at one FrontForearm.R key); a wrongly mapped bone
    # misses every key, so more than 1 in 20 missing fails.
    if not checked or len(mismatched) * 20 > checked:
        raise ValueError(f'Godot bone locals are not the GLB rotations: {mismatched[:5]} of {checked}')
    original_json = json.dumps(gl, sort_keys=True)
    original_bin = bytes(binary)
    input_index = None
    for name in sorted(keys['bones']):
        sampler = mine[(name, 'rotation')][0]
        values = np.array(keys['bones'][name]['rotation'], dtype=np.float64)
        if values.shape != (len(times), 4) or np.abs(np.linalg.norm(values, axis=1) - 1).max() > 1e-4:
            raise ValueError(f'{name}: expected {len(times)} unit quaternions')
        if np.abs(values[-1] - values[0]).max() > TOL and np.abs(values[-1] + values[0]).max() > TOL:
            raise ValueError(f'{name}: the loop seam is not closed')
        if input_index is None:
            input_index = _append(gl, binary, times[:, None], gl['accessors'][sampler['input']])
        sampler['input'] = input_index
        sampler['interpolation'] = 'LINEAR'
        sampler['output'] = _append(gl, binary, values, gl['accessors'][sampler['output']])
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
    return write(gl, binary), len(keys['bones']), len(times), (checked, mismatched)


def main():
    shipped, keyed = Path(sys.argv[1]), Path(sys.argv[2])
    data, n, count, checked = transplant(shipped.read_bytes(), json.loads(keyed.read_text()))
    shipped.write_bytes(data)
    print('TRANSPLANTED', n, 'MARCH rotation channels,', count, 'keys each, into', shipped,
          f'({checked[0] - len(checked[1])} of {checked[0]} shipped keys matched Godot; resampled by the import: {checked[1]})')


if __name__ == '__main__':
    main()
