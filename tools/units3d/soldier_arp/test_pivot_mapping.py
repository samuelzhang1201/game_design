#!/usr/bin/env python3
"""The shipped infantry pivot pair is the coupled mapping's solve, baked losslessly (no Godot needed).

1. The uncoupled parameters rebuild the frozen (knight) feasibility references exactly (the port is faithful).
2. The canonical pair rebuilt from the committed captures of the installed infantry passes the R-B skin
   and R-A contact audit.
3. Baking the committed solve onto the installed GLB's own ten-clip prefix reproduces it byte for byte.
4. The committed runtime plan (infantry_pivot_plan.json) is what the mapping generates.
"""
import base64
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import zlib

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import pivot  # noqa: E402
import pivot_mapping as pm  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / 'tests/fixtures/infantry_pivot_mapping.json'
GLB = ROOT / 'assets/3D/units/infantry/infantry.glb'
PLAN = ROOT / 'assets/3D/units/infantry/infantry_pivot_plan.json'
HASHES = {'baseline-native.json': '688f12a453bbab9246178e526a15c07f762565597b14d26d1b44b30703de0108',
          'native-march.json': 'ab62ebdf47772df1cf7642aaf6941d0a016a17644b74099a53ff526ee0caac97',
          'canonical-samples.json': '6613f23f4c4dac0e14749ededee30be8f8a70429a45163c4c13643f1d46bcb3b'}
MAIN_GLB_SHA256 = 'b94d3fbbebfebac60fe8bc9ab2f93e4538e569b4dbc4c9ff18745fb7cfb38acf'  # ten clips (game_export.py)
OLD = {'animations': 10, 'accessors': 2117, 'bufferViews': 2120, 'binary': 5757072}


def sources():
    fixture = json.loads(FIXTURE.read_text())
    assert fixture['format'] == 'infantry-pivot-mapping-v2' and set(fixture['sources']) == set(HASHES)
    out = {}
    for name, sha in HASHES.items():
        s = fixture['sources'][name]
        raw = zlib.decompress(base64.b64decode(s['zlib_base64'], validate=True))
        assert len(raw) == s['bytes'] and hashlib.sha256(raw).hexdigest() == sha == s['sha256'], name
        out[name] = json.loads(raw)
    return out


def bare_source(path, out):
    """The installed GLB minus the appended pair: exactly the ten-clip export pivot.bake read."""
    data, binary = pivot._read(path)
    assert [a['name'] for a in data['animations'][OLD['animations']:]] == ['PIVOT_RIGHT', 'PIVOT_LEFT']
    data['animations'] = data['animations'][:OLD['animations']]
    data['accessors'] = data['accessors'][:OLD['accessors']]
    data['bufferViews'] = data['bufferViews'][:OLD['bufferViews']]
    binary = binary[:OLD['binary']]
    data['buffers'][0]['byteLength'] = len(binary)
    header = json.dumps(data, separators=(',', ':')).encode()
    header += b' ' * (-len(header) % 4)
    out.write_bytes(b''.join([b'glTF', (2).to_bytes(4, 'little'), (28 + len(header) + len(binary)).to_bytes(4, 'little'),
                              len(header).to_bytes(4, 'little'), b'JSON', header,
                              len(binary).to_bytes(4, 'little'), b'BIN\0', binary]))


def close(a, b):
    if isinstance(a, dict):
        return a.keys() == b.keys() and all(close(a[k], b[k]) for k in a)
    if isinstance(a, list):
        return len(a) == len(b) and all(close(x, y) for x, y in zip(a, b))
    if isinstance(a, float) or isinstance(b, float):
        return abs(a - b) < 1e-9
    return a == b


def main():
    pm.self_check(pm.frozen_model())
    data = sources()
    model = pm.installed_model(data['baseline-native.json'], [data['native-march.json']])
    cases = pm.build(model)
    report = pm.audit(model, cases, data['canonical-samples.json'])
    for row in report:
        assert row['pass'] and row['skin']['introduced'] == 0, row
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        bare_source(GLB, tmp / 'source.glb')
        assert hashlib.sha256((tmp / 'source.glb').read_bytes()).hexdigest() == MAIN_GLB_SHA256, 'old ten changed'
        (tmp / 'samples.json').write_text(json.dumps(data['canonical-samples.json']))
        pivot.bake(tmp / 'source.glb', tmp / 'samples.json', tmp / 'out.glb', 4.0)
        mine, theirs = (tmp / 'out.glb').read_bytes(), GLB.read_bytes()
        if mine != theirs:  # another BLAS may round a float32 key differently: compare values
            (a, ab), (b, bb) = pivot._read(tmp / 'out.glb'), pivot._read(GLB)
            assert a == b and ab[:OLD['binary']] == bb[:OLD['binary']], 'installed GLB is not the committed bake'
            x, y = (np.frombuffer(v[OLD['binary']:], '<f4') for v in (ab, bb))
            assert len(x) == len(y) and float(np.abs(x - y).max()) < 2e-6, 'installed GLB is not the committed bake'
    committed = json.loads(PLAN.read_text())
    mine = pm.encode([{k: g[k] if k not in ('sole', 'toe') else g[k][:3, :3] for k in g} for g in cases[0]['plan']])
    assert committed['march_phase'] == pm.CANONICAL_PHASE and committed['rest'] == pm.encode(cases[0]['rest'])
    assert close(committed['legs'], mine), 'infantry_pivot_plan.json is stale: rerun pivot_mapping.py plan'
    print('PIVOT_MAPPING_MATCH', json.dumps([{k: r[k] for k in ('turn_udeg', 'skin', 'contact_um')} for r in report]))


if __name__ == '__main__':
    main()
