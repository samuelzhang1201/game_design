#!/usr/bin/env python3
"""Offline custody controls; no native or physical acceptance."""
import copy
import base64
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
import zlib

try:
    import pivot_contact_evidence as custody
except ModuleNotFoundError:
    custody = None


def sha(data):
    return hashlib.sha256(data).hexdigest()


class CustodyTest(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(custody, 'offline custody verifier must exist')

    def test_exact_decode_across_compressed_part_boundaries(self):
        raw = bytes(range(256)) * 10000
        packed = zlib.compress(raw)
        output = io.BytesIO()
        result = custody.decode([packed[:1], packed[1:17], packed[17:-1], packed[-1:]],
                                output.write, len(raw), sha(raw))
        self.assertEqual(output.getvalue(), raw)
        self.assertEqual(result, {'bytes': len(packed), 'sha256': sha(packed)})

    def test_truncated_trailing_and_size_or_hash_mismatch_rejected(self):
        raw = b'bounded output\n' * 200000
        packed = zlib.compress(raw)
        controls = [(packed[:-1], len(raw), sha(raw)),
                    (packed+b'trailing', len(raw), sha(raw)),
                    (packed+zlib.compress(b''), len(raw), sha(raw)),
                    (packed, len(raw)-1, sha(raw)),
                    (packed, len(raw)+1, sha(raw)),
                    (packed, len(raw), '0'*64)]
        for data, size, digest in controls:
            with self.subTest(size=size, digest=digest, tail=data[-10:]):
                with self.assertRaises(ValueError):
                    custody.decode([data], lambda _: None, size, digest)

    def test_safe_paths_and_symlinks(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            for name in ['/tmp/escape', '../escape', 'x/../escape', './x', 'x//y',
                         'x\\y', '', 'C:/escape']:
                with self.subTest(name=name), self.assertRaises(ValueError):
                    custody.safe_path(root, name)
            (root/'link').symlink_to(root, target_is_directory=True)
            with self.assertRaises(ValueError):
                custody.safe_path(root, 'link/escape')
            self.assertEqual(custody.safe_path(root, 'native-parts/part0.jsonl'),
                             root/'native-parts/part0.jsonl')

    def test_exact_asset_inventory_hash_size_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            (root/'one').write_bytes(b'first')
            specs = [{'asset_name': 'one', 'bytes': 5, 'sha256': sha(b'first')}]
            custody.verify_assets(specs, root)
            for mutation in ['corrupt', 'missing', 'extra', 'duplicate', 'size', 'hash', 'symlink']:
                with self.subTest(mutation=mutation):
                    data = copy.deepcopy(specs)
                    if mutation == 'corrupt': (root/'one').write_bytes(b'other')
                    if mutation == 'missing': (root/'one').unlink()
                    if mutation == 'extra': (root/'extra').write_bytes(b'extra')
                    if mutation == 'duplicate': data += data
                    if mutation == 'size': data[0]['bytes'] = True
                    if mutation == 'hash': data[0]['sha256'] = 'X'*64
                    if mutation == 'symlink':
                        (root/'one').unlink(); (root/'one').symlink_to(root/'extra')
                    with self.assertRaises(ValueError): custody.verify_assets(data, root)
                    for child in root.iterdir(): child.unlink()
                    (root/'one').write_bytes(b'first')
            with self.assertRaises(FileExistsError):
                custody.write_new(root/'one', b'replace')
            self.assertEqual((root/'one').read_bytes(), b'first')

    def test_native_part_boundaries_counts_order_and_digest(self):
        rows = [b'{"ordinal":0}\n', b'{"ordinal":1}\n']
        parts = [{'bytes': len(row), 'raw_offset': sum(map(len, rows[:i])),
                  'first_ordinal': i, 'row_count': 1, 'sha256': sha(row),
                  'logical_path': f'native-parts/part{i:05d}.jsonl'}
                 for i, row in enumerate(rows)]
        ledger = {'parts': parts, 'rows': 2, 'raw_bytes': sum(map(len, rows))}
        self.assertEqual(custody.verify_native_parts(io.BytesIO(b''.join(rows)), ledger), 2)
        for change in ['order', 'digest', 'count', 'offset', 'extra', 'truncated']:
            wrong = copy.deepcopy(ledger); data = b''.join(rows)
            if change == 'order': wrong['parts'].reverse()
            if change == 'digest': wrong['parts'][0]['sha256'] = '0'*64
            if change == 'count': wrong['parts'][0]['row_count'] = 2
            if change == 'offset': wrong['parts'][1]['raw_offset'] += 1
            if change == 'extra': data += b'extra'
            if change == 'truncated': data = data[:-1]
            with self.subTest(change=change), self.assertRaises(ValueError):
                custody.verify_native_parts(io.BytesIO(data), wrong)

    def test_manifest_ordered_groups_reject_reuse_and_unsafe_destination(self):
        manifest = {'assets': [{'asset_name': n, 'bytes': 1, 'sha256': sha(b'x')}
                               for n in ['a', 'b']], 'assets_total_bytes': 2,
                    'stream_groups': {'responses': {'ordered_parts': ['a', 'b'],
                        'compressed_bytes': 2, 'compressed_sha256': sha(b'xx'),
                        'decoded_bytes': 3, 'decoded_sha256': sha(b'raw'),
                        'logical_cache_path': 'responses.json'}}}
        custody.validate_groups(manifest)
        for change in ['duplicate', 'unknown', 'bytes', 'path', 'hash']:
            wrong = copy.deepcopy(manifest); g = wrong['stream_groups']['responses']
            if change == 'duplicate': g['ordered_parts'] = ['a', 'a']
            if change == 'unknown': g['ordered_parts'] = ['a', 'c']
            if change == 'bytes': g['compressed_bytes'] = 3
            if change == 'path': g['logical_cache_path'] = '../escape'
            if change == 'hash': g['decoded_sha256'] = 'invalid'
            with self.subTest(change=change), self.assertRaises(ValueError):
                custody.validate_groups(wrong)

    def test_payload_hash_encoding_and_decoded_limit(self):
        raw = b'opaque script bytes; never execute'
        packed = zlib.compress(raw)
        payload = {'encoding': 'zlib+base64', 'data_base64': base64.b64encode(packed).decode(),
                   'decoded_bytes': len(raw), 'sha256': sha(raw), 'compressed_sha256': sha(packed)}
        self.assertEqual(custody.payload_bytes(payload), raw)
        for key, value in [('encoding', 'other'), ('decoded_bytes', 1), ('sha256', '0'*64),
                           ('compressed_sha256', '0'*64), ('data_base64', 'invalid')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                custody.payload_bytes(dict(payload, **{key: value}))

    def test_original_request_chunk_receipt_binding(self):
        spec = {'first_ordinal': 0, 'row_count': 1, 'request_sha256': sha(b'row\n')}
        chunk = {'chunk_index': 0, 'first_ordinal': 0, 'row_count': 1, 'sha256': sha(b'row\n')}
        custody.check_request_chunk(chunk, 0, spec)
        for key, value in [('chunk_index', 1), ('first_ordinal', 1), ('row_count', 2), ('sha256', '0'*64)]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                custody.check_request_chunk(dict(chunk, **{key: value}), 0, spec)

    def test_restore_and_all_three_unmodified_stream_replays(self):
        import pivot_metrics as metric
        def payload(raw):
            packed = zlib.compress(raw)
            return {'encoding': 'zlib+base64', 'data_base64': base64.b64encode(packed).decode(),
                    'decoded_bytes': len(raw), 'sha256': sha(raw), 'compressed_sha256': sha(packed)}
        def data(value): return json.dumps(value).encode()
        req = {'ordinal': 0, 'role': 'vertex'}
        header = dict.fromkeys(['observation_header_sha256', 'fixture_sha256', 'surface_manifest_sha256'], sha(b''))
        header['evidence'] = {}
        requests = io.BytesIO(); rf = metric.write_query_stream(requests, 'requests', header, [req])
        response = {'request': req, 'status': 'OK', 'raw_word': '01234567'}
        responses = io.BytesIO(); sf = metric.write_query_stream(responses, 'responses',
            dict(header, request_stream_sha256=rf['stream_sha256']), [response])
        utf8 = metric.compact(req)
        raw_native = metric.compact({'request_utf8': utf8.decode(), 'request_sha256': sha(utf8),
                                    'response': {k:v for k,v in response.items() if k != 'request'}})+b'\n'
        manifest = {'schema': 'infantry-contact-custody/v1', 'asset_cap_bytes': custody.ASSET_CAP,
            'repository': 'owner/repo', 'release_tag': 'tag', 'assets': [], 'assets_total_bytes': 0,
            'stream_groups': {}, 'context_packet_asset': 'context.zlib', 'baseline_asset_names': ['baseline.zlib'],
            'actual_context_PNG_assets': [{'job': 0, 'asset_name': 'context.png', 'logical_cache_path': 'contexts/0.png'}],
            'portable_native_ledger_payload': 'ledger.json', 'frozen_source_manifest_payload': 'frozen.json',
            'native_raw': {'parts': 1, 'rows': 1}, 'strict_Gram': 'FAIL', 'physical_uncertainty': 'UNKNOWN',
            'E': None, 'motion_acceptance': 'FAIL/PENDING',
            'C_response_transport': {'rows': 1, 'footer': sf, 'context_count': 1, 'request_stream_sha256': rf['stream_sha256']},
            'original_request_file': {'canonical_request_rowstream_sha256': rf['stream_sha256']}}
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve(); assets = root/'assets'; assets.mkdir()
            def asset(name, raw):
                (assets/name).write_bytes(raw)
                spec = {'asset_name': name, 'bytes': len(raw), 'sha256': sha(raw),
                        'url': 'https://github.com/owner/repo/releases/download/tag/'+name}
                manifest['assets'].append(spec); manifest['assets_total_bytes'] += len(raw)
                return spec
            for name, raw, path in [('original_requests', requests.getvalue(), 'requests.json'),
                                    ('responses', responses.getvalue(), 'responses.json'),
                                    ('native_raw', raw_native, 'native-raw.jsonl')]:
                packed = zlib.compress(raw); part = name+'.part'; asset(part, packed)
                manifest['stream_groups'][name] = {'ordered_parts': [part], 'compressed_bytes': len(packed),
                    'compressed_sha256': sha(packed), 'decoded_bytes': len(raw), 'decoded_sha256': sha(raw),
                    'logical_cache_path': path}
            baseline = data({'prior': payload(b'original failure')}); packed = zlib.compress(baseline)
            spec = asset('baseline.zlib', packed)
            meta = dict(spec, decoded_bytes=len(baseline), decoded_sha256=sha(baseline), source_file='baseline.zlib')
            ledger = {'raw_bytes': len(raw_native), 'rows': 1, 'parts': [{'raw_offset': 0, 'first_ordinal': 0,
                'row_count': 1, 'bytes': len(raw_native), 'sha256': sha(raw_native), 'logical_path': 'native-parts/part0.jsonl'}]}
            files = {'proposal-source/measured-response-and-baseline-assets.json': payload(data({'baseline_assets': [meta]})),
                     'ledger.json': payload(data(ledger)),
                     'frozen.json': payload(data({'required_vertex_rows': 1, 'required_anchor_rows': 0}))}
            original = {'first_ordinal': 0, 'row_count': 1, 'request_sha256': sha(utf8+b'\n'),
                        'request_path': '/historical/request', 'response_path': '/historical/response'}
            original_raw = data(original)+b'\n'
            jobroot = 'run/native-execution/'
            files[jobroot+'native-job-plan.json'] = payload(data({'jobs': [
                {'index': 0, 'parts_sha256': sha(original_raw), 'part_count': 1}]}))
            files[jobroot+'jobs/job00000/parts.jsonl'] = payload(original_raw)
            files[jobroot+'jobs/job00000/receipts.jsonl'] = payload(data(dict(original, response_sha256=sha(raw_native)))+b'\n')
            packet = data({'schema': 'infantry-contact-custody-context/v1', 'files': files})
            asset('context.zlib', zlib.compress(packet)); asset('context.png', b'opaque PNG bytes')
            cache = root/'cache'
            result = custody.restore(manifest, assets, cache)
            self.assertEqual(result['native_parts'], 1)
            self.assertEqual(result['baseline_payloads'], 1)
            self.assertEqual((cache/'contexts/0.png').read_bytes(), b'opaque PNG bytes')
            with self.assertRaises(ValueError): custody.restore(manifest, assets, cache)
            for kind in ['requests', 'responses', 'native']:
                self.assertEqual(custody.replay(manifest, cache, kind)['counts'], {'vertex': 1, 'anchor': 0})
                with self.assertRaises(ValueError): custody.replay(manifest, cache, kind)


if __name__ == '__main__':
    unittest.main()
