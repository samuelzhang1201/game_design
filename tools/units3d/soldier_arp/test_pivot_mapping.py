#!/usr/bin/env python3
"""The shipped infantry pivot pair is the coupled mapping's solve, baked losslessly (no Godot needed).

1. The uncoupled parameters rebuild the frozen (knight) feasibility references exactly (the port is faithful).
2. The canonical pair rebuilt from the committed captures of the installed infantry passes the R-B skin
   and R-A contact audit.
3. Baking the committed solve onto the installed GLB's own nineteen-clip prefix reproduces it byte for byte.
4. The committed runtime plan (infantry_pivot_plan.json) is what the mapping generates.
2-4 hold for every arm on the rig contract (ARMS: the infantry, the heavy infantry and the axemen).
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
# per arm: the committed captures' hashes, the nineteen-clip export (game_export.py) and its sizes
ARMS = {
    'infantry': {
        'hashes': {'baseline-native.json': '62922f40c2bb48668a86ac11cb13cdb9fde791623685de1176c613ae777b24cc',
                   'native-march.json': '9ddf149a2627a7fa4a0e75abc8b9134ca004b9c97e1d1876c8d9652310d2b370',
                   'canonical-samples.json': 'a28adcaa27a5195c37a09848b7c6766e4bf2825ea8fc0631b2a96692e2960176'},
        'glb_sha256': 'cde6b05ecd06ec9cd3cfa4989dd0100a431b47d6923b94c8a52f28c6eec46ef3',
        'old': {'animations': 19, 'accessors': 4015, 'bufferViews': 4018, 'binary': 6525568}},
    'heavy_infantry': {
        'hashes': {'baseline-native.json': '2455c300d486217ac0882a42506ed152c8829298b6465bd0717c706a85dc433e',
                   'native-march.json': '4f4d4d4c68c1f7cd4225d867e763a8350a7bba2bf72377161876e5dd86742a35',
                   'canonical-samples.json': '795711ba5352dd9e093bf924e742b8fa2439e38d859037c20118eb42d10716aa'},
        'glb_sha256': '899ecf39af52019db6a273f8ea35badc9d94455e8d25a60c316b59f46086343f',
        'old': {'animations': 19, 'accessors': 4015, 'bufferViews': 4018, 'binary': 5776552}},
    'axemen': {
        'hashes': {'baseline-native.json': '8bfd9acadf4e17c2cf417e889455fd36cb3040be0ba33abc809eb4919bbdf7d1',
                   'native-march.json': '2da85fa15bb11016597037050ae7a33563f545ccb548c2a961d377fdf1582475',
                   'canonical-samples.json': 'f71b54f6e5ba42e2e0101f08a7d3b9b6111d8550a9a6cb14d9e22d218927c58f'},
        'glb_sha256': 'c69bb9e6dc20642590e471ffc03a0dff752f0c4e563bdf948a622e4c4c3087d3',
        'old': {'animations': 19, 'accessors': 4015, 'bufferViews': 4018, 'binary': 6602724}},
}


def bind(arm):
    global FIXTURE, GLB, PLAN, HASHES, MAIN_GLB_SHA256, OLD
    pm.use(arm)
    FIXTURE = ROOT / f'tests/fixtures/{arm}_pivot_mapping.json'
    GLB = ROOT / f'assets/3D/units/{arm}/{arm}.glb'
    PLAN = ROOT / f'assets/3D/units/{arm}/{arm}_pivot_plan.json'
    HASHES, MAIN_GLB_SHA256, OLD = (ARMS[arm][k] for k in ('hashes', 'glb_sha256', 'old'))


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
    """The installed GLB minus the appended pair: exactly the nineteen-clip export pivot.bake read."""
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
    for arm in ARMS:
        bind(arm)
        check(arm)


def check(arm):
    data = sources()
    model = pm.installed_model(data['baseline-native.json'], [data['native-march.json']])
    cases = pm.build(model)
    report = pm.audit(model, cases, data['canonical-samples.json'])
    for row in report:
        assert row['pass'] and row['skin']['introduced'] == 0, row
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        bare_source(GLB, tmp / 'source.glb')
        assert hashlib.sha256((tmp / 'source.glb').read_bytes()).hexdigest() == MAIN_GLB_SHA256, 'old nineteen changed'
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
    # the rest is built from the GLB's joints by numpy: another BLAS rounds its last bits apart
    assert committed['march_phase'] == pm.CANONICAL_PHASE and close(committed['rest'], pm.encode(cases[0]['rest'])), \
        'infantry_pivot_plan.json rest is stale: rerun pivot_mapping.py plan'
    assert close(committed['legs'], mine), 'infantry_pivot_plan.json is stale: rerun pivot_mapping.py plan'
    print('PIVOT_MAPPING_MATCH', arm, json.dumps([{k: r[k] for k in ('turn_udeg', 'skin', 'contact_um')} for r in report]))


if __name__ == '__main__':
    main()
