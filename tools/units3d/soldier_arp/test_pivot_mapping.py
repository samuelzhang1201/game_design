#!/usr/bin/env python3
"""The shipped infantry pivot pair is the coupled mapping's solve, baked losslessly (no Godot needed).

1. The uncoupled parameters rebuild the frozen feasibility references exactly (the port is faithful).
2. The canonical pair rebuilt from the committed captures passes the R-B skin and R-A contact audit.
3. Baking the committed solve onto the installed GLB's own five-clip prefix reproduces it byte for byte.
"""
import base64
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import zlib

sys.path.insert(0, str(Path(__file__).parent))
import pivot  # noqa: E402
import pivot_mapping as pm  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / 'tests/fixtures/infantry_pivot_mapping.json'
GLB = ROOT / 'assets/3D/units/infantry/infantry.glb'
HASHES = {'native-march.json': '2c04d2b90d5dfe28ed23b316f7a46762bd0daa3a08d89033bce846fa8c640b98',
          'canonical-samples.json': '1e1ac9d5f58c3e9705bde79ddcc0a8289175c2f9c1a0df29b036f24071778020'}
OLD = {'animations': 5, 'accessors': 1047, 'bufferViews': 1050, 'binary': 3837556}


def sources():
    fixture = json.loads(FIXTURE.read_text())
    assert fixture['format'] == 'infantry-pivot-mapping-v1' and set(fixture['sources']) == set(HASHES)
    out = {}
    for name, sha in HASHES.items():
        s = fixture['sources'][name]
        raw = zlib.decompress(base64.b64decode(s['zlib_base64'], validate=True))
        assert len(raw) == s['bytes'] and hashlib.sha256(raw).hexdigest() == sha == s['sha256'], name
        out[name] = json.loads(raw)
    return out


def bare_source(path, out):
    """The installed GLB minus the appended pair: exactly the five-clip export pivot.bake read."""
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


def main():
    model = pm.Model(pm.load_frozen())
    pm.self_check(model)
    data = sources()
    model = pm.Model(pm.load_frozen(), [data['native-march.json']])
    cases = pm.build(model)
    report = pm.audit(model, cases, data['canonical-samples.json'])
    for row in report:
        assert row['pass'] and row['skin']['introduced'] == 0, row
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        bare_source(GLB, tmp / 'source.glb')
        (tmp / 'samples.json').write_text(json.dumps(data['canonical-samples.json']))
        pivot.bake(tmp / 'source.glb', tmp / 'samples.json', tmp / 'out.glb', 4.0)
        assert (tmp / 'out.glb').read_bytes() == GLB.read_bytes(), 'installed GLB is not the committed bake'
    print('PIVOT_MAPPING_MATCH', json.dumps([{k: r[k] for k in ('turn_udeg', 'skin', 'contact_um')} for r in report]))


if __name__ == '__main__':
    main()
