#!/usr/bin/env python3
"""Replay frozen native LBS counterexamples, never certify motion (stdlib only).

Run directly; --self-check checks arithmetic and rejection paths without replay.
Exit 0 means reproduction matched, while the printed motion verdict stays FAIL.
"""
import argparse
import base64
import copy
import hashlib
import json
import math
from pathlib import Path
import sys
import struct
import zlib

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / 'tests/fixtures/infantry_pivot_feasibility.json'
HASHES = {
    'prerequisite-proposal.md': 'c5f76a472c6933910672e7f0875ea59c8cd55ce4bd29aca4da211c46e6dc7c2f',
    'prerequisite-evidence-manifest.json': 'ff97d2c95b24c0830c3c52e6b06c0e1d796295c8f9aa4c51a52a38eb32ea3a67',
    'round1_actual_march/native-march.json': 'fa971d07a79dfed75d0ff55fbe3997c3268bc04c9b140f2530517f60ad4e3b60',
    'round1_arc_combined/inputs.json': 'c120cd488b576c749e02f733dccfbeed4844bf243b5ba60d5934d0114ee4927e',
    'round1_arc_combined/results.json': 'cfda3b41468d27cb3c221a68b9343e9b8bbadc85f8ba1c09a0e62e59c9a5b31c',
    'round1_arc_combined/edge-attribution.json': '422de4de30cb037eecd0a473d95905b527073f5fa93f886fb891f337c4f4f8b9',
    'round1_actual_march/contact-frame-report.json': 'd3857558a3247b98491f26538efc9c70937321f6b88ecfc1e0c594f4329db626',
    'native_import_probe/baseline-native.json': '34bed95c453b4a12ae49b5baa507baa62f909d8ebdc5219f22249f8b7e8790cd',
    'provider216_probe/provider216-diagnostic-native.json': 'acc6b827b9a1e6752aca91b3b8d3ebfa0c44b8d64803f7fa3c2f3a1b1efc1a94',
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def close(a, b):
    # Arithmetic replay tolerance, never a contact or edge acceptance tolerance.
    require(math.isfinite(a) and math.isfinite(b) and abs(a - b) < 1e-10,
            f'replay mismatch: {a} != {b}')


def decode_source(source, expected):
    require(source['sha256'] == expected, 'unrecognized source hash')
    raw = zlib.decompress(base64.b64decode(source['zlib_base64'], validate=True))
    require(len(raw) == source['bytes'], 'source size mismatch')
    require(hashlib.sha256(raw).hexdigest() == expected, 'source bytes changed')
    return raw


def load_fixture(path):
    fixture = json.loads(path.read_text())
    require(fixture['format'] == 'infantry-pivot-feasibility-v1', 'unknown fixture format')
    require(set(fixture['sources']) == set(HASHES), 'missing/extra source')
    raw = {name: decode_source(fixture['sources'][name], sha) for name, sha in HASHES.items()}
    manifest = json.loads(raw['prerequisite-evidence-manifest.json'])
    require(fixture['manifest'] == manifest, 'frozen manifest changed')
    for name, sha in manifest.items():
        if name in raw:
            require(hashlib.sha256(raw[name]).hexdigest() == sha, 'manifest mismatch')
    return {name: json.loads(value) for name, value in raw.items() if name.endswith('.json')}


def mul(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def globals_of(local, parents):
    require(set(local) == set(parents), 'pose/hierarchy names differ')
    result = {}
    visiting = set()

    def visit(name):
        if name not in result:
            require(name not in visiting, 'cyclic hierarchy')
            visiting.add(name)
            parent = parents[name]
            result[name] = mul(visit(parent), local[name]) if parent else local[name]
            visiting.remove(name)
        return result[name]

    for name in local:
        visit(name)
    return result


class Skin:
    def __init__(self, geometry):
        require(len(geometry['surfaces']) == 1, 'unexpected surface count')
        self.surface = geometry['surfaces'][0]
        self.binds = geometry['binds']
        self.names = [b['name'] for b in self.binds]
        s = self.surface
        n = len(s['vertices'])
        require(n == 20880 and len(s['bones']) == len(s['weights']) == n * 4,
                'incomplete native mesh/influences')
        require(len(set(self.names)) == len(self.names) == 69, 'invalid bind names')
        require(all(type(j) is int and 0 <= j < 69 for j in s['bones']), 'invalid bone index')
        require(all(math.isfinite(w) and w >= 0 for w in s['weights']), 'invalid weight')
        require(all(sum(s['weights'][i:i + 4]) > 0 for i in range(0, n * 4, 4)), 'zero weight sum')
        require(all(len(v) == 3 and all(math.isfinite(x) for x in v) for v in s['vertices']), 'invalid vertex')
        require(len(s['indices']) % 3 == 0 and all(type(i) is int and 0 <= i < n for i in s['indices']), 'invalid triangle')
        edges = set()
        for i in range(0, len(s['indices']), 3):
            a, b, c = s['indices'][i:i + 3]
            edges.update(tuple(sorted(e)) for e in [(a, b), (b, c), (c, a)])
        self.edges = sorted(edges)

    def points(self, globals_):
        matrices = [mul(globals_[b['name']], b['pose']) for b in self.binds]
        s = self.surface
        result = []
        for i, (x, y, z) in enumerate(s['vertices']):
            px = py = pz = 0.0
            for k in range(4):
                offset = 4 * i + k
                m = matrices[s['bones'][offset]]
                w = s['weights'][offset]
                px += (m[0][0]*x + m[0][1]*y + m[0][2]*z + m[0][3]) * w
                py += (m[1][0]*x + m[1][1]*y + m[1][2]*z + m[1][3]) * w
                pz += (m[2][0]*x + m[2][1]*y + m[2][2]*z + m[2][3]) * w
            result.append((px, py, pz))
        return result

    def lengths(self, points):
        return [math.dist(points[a], points[b]) for a, b in self.edges]

    def floor(self, points):
        s = self.surface
        boots = [{self.names.index('foot' + side), self.names.index('toes_01' + side)}
                 for side in ['.l', '.r']]
        # Selection of the captured boot surface only; LBS keeps every vertex/weight.
        return min(p[1] for boot in boots for i, p in enumerate(points)
                   if sum(s['weights'][4*i+k] for k in range(4) if s['bones'][4*i+k] in boot)
                   / sum(s['weights'][4*i:4*i+4]) > .5)


def exceeds(length, entry):
    return length > 4 * entry and length > .03


def replay(data):
    baseline = data['native_import_probe/baseline-native.json']
    geo = data['provider216_probe/provider216-diagnostic-native.json']
    require(baseline['surfaces'] == geo['surfaces'] and baseline['binds'] == geo['binds'], 'geometry captures differ')
    skin = Skin(baseline)
    native = data['round1_actual_march/native-march.json']
    samples = {s['id']: s for s in native['samples']}
    require(len(samples) == len(native['samples']) == 1301, 'native sample loss/duplicates')
    for s in samples.values():
        # Godot decimal JSON may round one ulp; the original hex request id is authoritative.
        close(float.fromhex(s['id']), s['requested_phase'])
        close(s['observed_time_s'], s['requested_phase'] * native['length_s'])

    def native_points(phase):
        key = float(phase).hex()
        require(key in samples, f'uncaptured native phase {key}; no interpolation')
        return skin.points(samples[key]['global_bones'])

    contacts = data['round1_actual_march/contact-frame-report.json']
    deltas = []
    for case in contacts['cases']:
        floors = [skin.floor(native_points(case[end]['requested_phase'])) for end in ['entry', 'exit']]
        for value, end in zip(floors, ['entry', 'exit']):
            close(value, case[end]['floor_min_y'])
        delta = floors[1] - floors[0]
        close(delta, case['contact_frame']['exit_native_skin_separation_from_same_entry_plane_m'])
        deltas.append(delta)
    inputs = data['round1_arc_combined/inputs.json']['cases']
    results = data['round1_arc_combined/results.json']['cases']
    attribution = data['round1_arc_combined/edge-attribution.json']
    require(attribution['threshold_unchanged'] == {'ratio': 4, 'absolute_m': .03}, 'gate changed')
    expected = {(r['turn_udeg'], r['phase'], r['edge_id_sorted_unique']): r
                for r in attribution['offending_edge_phase_pairs']}
    require(len(expected) == len(attribution['offending_edge_phase_pairs']) == 471, 'attribution loss/duplicates')
    require(len(inputs) == len(results) == 5, 'case loss')
    seen = set()
    introduced = mapping_only = frames = 0
    counts = {}
    peaks = {}
    witness = None
    mapping_only_keys = []
    whole_mesh_digest = hashlib.sha256()
    for case, result in zip(inputs, results):
        turn = case['op']['turn_udeg']
        entry, exit_ = [case['op'][key] for key in ['march_entry_phase', 'march_exit_phase']]
        require(not result['failures'] and turn == result['turn_udeg'], 'helper failure/case mismatch')
        require(len(case['phases']) == len(result['frames']) == len(case['reference_poses']) == 260, 'frame loss')
        parents = {b['name']: b['parent'] for b in case['rest']['bones']}
        require(len(parents) == len(case['rest']['bones']) == 70, 'hierarchy loss')
        pe = native_points(entry)
        lengths0 = skin.lengths(pe)
        for u, reference, frame in zip(case['phases'], case['reference_poses'], result['frames']):
            close(frame['phase'], u)
            mapped = skin.points(globals_of(frame['pose'], parents))
            whole_mesh_digest.update(b''.join(struct.pack('<3d', *p) for p in mapped))
            lengths = skin.lengths(mapped)
            bad = [k for k, (length, base) in enumerate(zip(lengths, lengths0)) if exceeds(length, base)]
            frames += 1
            if not bad:
                continue
            distance = 1.0 if entry == exit_ else (exit_ - entry) % 1.0
            phase = entry if u == 0 else exit_ if u == 1 else (entry + distance*u) % 1.0
            pn = native_points(phase)
            pr = skin.points(globals_of(reference, parents))
            counts[turn] = counts.get(turn, 0) + len(bad)
            peaks[turn] = max(peaks.get(turn, 0), len(bad))
            for edge_id in bad:
                key = (turn, u, edge_id)
                require(key in expected, f'unexpected failure {key}')
                row = expected[key]
                seen.add(key)
                edge = skin.edges[edge_id]
                require(list(edge) == row['vertices'], 'native edge order changed')
                for v, recorded in zip(edge, row['influences']):
                    actual = [{'bind': skin.surface['bones'][4*v+k],
                               'bone': skin.names[skin.surface['bones'][4*v+k]],
                               'weight': skin.surface['weights'][4*v+k]} for k in range(4)
                              if skin.surface['weights'][4*v+k] > 0]
                    require(actual == recorded, 'recorded influences differ from full native weights')
                values = {}
                for label, points in [('native_entry', pe), ('native_same_phase', pn), ('authored_reference', pr), ('mapped', mapped)]:
                    values[label] = math.dist(points[edge[0]], points[edge[1]])
                    close(values[label], row['length_m'][label])
                    if label != 'native_entry':
                        close(values[label] / values['native_entry'], row['ratio_to_native_entry'][label])
                    for v, recorded in zip(edge, row['positions'][label]):
                        for actual, wanted in zip(points[v], recorded):
                            close(actual, wanted)
                nbad = exceeds(values['native_same_phase'], values['native_entry'])
                rbad = exceeds(values['authored_reference'], values['native_entry'])
                require(nbad == row['native_same_phase_exceeds_gate'] and rbad == row['reference_exceeds_gate'], 'flag mismatch')
                introduced += not nbad
                mapping_only += not nbad and not rbad
                if not nbad and not rbad:
                    mapping_only_keys.append(key)
                if turn == -2000000 and u == .21 and edge_id == 6154:
                    require(list(edge) == [2756, 13448], 'cross-thigh witness changed')
                    witness = values
    require(seen == set(expected) and frames == 1300, 'incomplete full-mesh replay')
    require(introduced == 45 and mapping_only == 1 and witness is not None, 'attribution totals changed')
    require(mapping_only_keys == [(-2000000, .8775, 7315)], 'mapping-only witness changed')
    require(counts == {-2000000: 326, -1: 137, 90000000: 8}, 'failure counts changed')
    require(peaks == {-2000000: 3, -1: 3, 90000000: 1}, 'peak failures changed')
    return {'reproduction': 'MATCH', 'motion_acceptance': 'FAIL', 'authority_decision': 'PENDING',
            'vertices': 20880, 'mapped_frames': frames, 'edge_phase_flags': len(seen),
            'introduced': introduced, 'mapping_only_crossings': mapping_only,
            'counts': counts, 'peak_edges': peaks, 'endpoint_deltas_m': deltas, 'edge6154_u021_m': witness,
            'whole_mapped_mesh_sha256': whole_mesh_digest.hexdigest()}


def self_check():
    for entry, exit_, delta in [(.017208295843782147, .010848789595012797, -.00635950624876935),
                                (.013331374454381694, .015196844203696224, .00186546974931453),
                                (-.0010609559011084519, .010622999682407897, .01168395558351635)]:
        close(exit_ - entry, delta)
        for scale in [1, 2]:
            for translation in [-3.0, 0.0, 7.0]:
                close((scale*exit_ + translation) - (scale*entry + translation), scale*delta)
    require(not exceeds(.03, .001) and not exceeds(.04, .01) and exceeds(.040001, .01), 'strict AND gate')
    identity = [[float(r == c) for c in range(4)] for r in range(4)]
    geo = {'surfaces': [{'vertices': [[1., 2., 3.]] * 20880, 'bones': [0, 1, 0, 0] * 20880,
                          'weights': [.2, .3, 0., 0.] * 20880, 'indices': [0, 1, 2]}],
           'binds': [{'name': str(i), 'pose': identity} for i in range(69)]}
    skin = Skin(geo)
    g = {str(i): copy.deepcopy(identity) for i in range(69)}
    g['1'][0][3] = 2
    for actual, wanted in zip(skin.points(g)[0], (1.1, 1., 1.5)):
        close(actual, wanted)
    raw = b'frozen'
    source = {'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw),
              'zlib_base64': base64.b64encode(zlib.compress(raw)).decode()}
    require(decode_source(source, source['sha256']) == raw, 'lossless decode')
    for mutate in [lambda s: s.update(bytes=1), lambda s: s.update(sha256='0'*64),
                   lambda s: s.update(zlib_base64='invalid!')]:
        bad = dict(source)
        mutate(bad)
        try:
            decode_source(bad, source['sha256'])
        except (ValueError, zlib.error):
            continue
        raise ValueError('invalid source accepted')
    geo['surfaces'][0]['bones'][0] = 69
    try:
        Skin(geo)
    except ValueError:
        return
    raise ValueError('invalid mesh accepted')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixture', type=Path, default=FIXTURE)
    parser.add_argument('--self-check', action='store_true')
    args = parser.parse_args()
    self_check()
    if args.self_check:
        print('SELF_CHECK_MATCH; no motion acceptance evaluated')
    else:
        print(json.dumps(replay(load_fixture(args.fixture)), sort_keys=True, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, IndexError, OSError, zlib.error) as error:
        print(f'REPRODUCTION_ERROR: {error}; motion acceptance NOT PASSED', file=sys.stderr)
        sys.exit(1)
