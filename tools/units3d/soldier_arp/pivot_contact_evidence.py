#!/usr/bin/env python3
"""Offline, lossless custody for the frozen infantry capture. Never executes evidence.

Download the exact manifest assets separately. `restore` requires a new cache;
`replay` uses the unchanged accepted QueryStream, never the geometry evaluator.
"""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import sys
import zlib

BLOCK = 1024 * 1024
ASSET_CAP = 100 * 1024 * 1024
PAYLOAD_CAP = 128 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise ValueError(message)


def size(value):
    require(type(value) is int and value >= 0, 'invalid byte/row count')
    return value


def digest(value):
    require(isinstance(value, str) and re.fullmatch('[0-9a-f]{64}', value), 'invalid SHA256')
    return value


def safe_path(root, name):
    require(isinstance(name, str) and name and '\\' not in name and ':' not in name
            and not PurePosixPath(name).is_absolute()
            and all(p not in ('', '.', '..') for p in name.split('/')), 'unsafe logical path')
    root = Path(root)
    target = root
    require(not any(p.is_symlink() for p in [root, *root.parents]), 'symlink cache root/parent')
    for part in name.split('/'):
        target /= part
        require(not target.is_symlink(), 'symlink logical path')
    return target


def write_new(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as output:
        output.write(data)


def blocks(path):
    with path.open('rb') as source:
        while data := source.read(BLOCK):
            yield data


def verified_blocks(directory, spec):
    sha, count = hashlib.sha256(), 0
    for data in blocks(safe_path(directory, spec['asset_name'])):
        sha.update(data); count += len(data)
        yield data
    require(count == spec['bytes'] and sha.hexdigest() == spec['sha256'], 'asset changed during restoration')


def fingerprint(chunks):
    count, sha = 0, hashlib.sha256()
    for data in chunks:
        count += len(data)
        sha.update(data)
    return {'bytes': count, 'sha256': sha.hexdigest()}


def asset_specs(specs):
    require(isinstance(specs, list) and 0 < len(specs) <= 1000, 'invalid asset count')
    result = {}
    for spec in specs:
        name = spec['asset_name']
        safe_path(Path('.'), name)
        require('/' not in name and name not in result, 'duplicate/nonflat asset name')
        require(0 < size(spec['bytes']) < ASSET_CAP, 'asset reaches byte cap')
        digest(spec['sha256'])
        result[name] = spec
    return result


def verify_assets(specs, directory):
    expected = asset_specs(specs)
    require(not directory.is_symlink() and directory.is_dir(), 'invalid asset directory')
    require({p.name for p in directory.iterdir()} == set(expected), 'missing/extra assets')
    for name, spec in expected.items():
        path = safe_path(directory, name)
        require(path.is_file(), 'asset is not a regular file')
        require(fingerprint(blocks(path)) == {'bytes': spec['bytes'], 'sha256': spec['sha256']},
                'asset byte/hash mismatch: '+name)


def decode(chunks, write, decoded_bytes, decoded_sha256):
    """One zlib stream, bounded output chunks, strict EOF and exact byte ceiling."""
    limit, wanted = size(decoded_bytes), digest(decoded_sha256)
    decoder = zlib.decompressobj()
    compressed, decoded = hashlib.sha256(), hashlib.sha256()
    total = packed = 0
    try:
        for data in chunks:
            packed += len(data)
            compressed.update(data)
            require(not decoder.eof or not data, 'trailing compressed bytes')
            while data:
                output = decoder.decompress(data, min(BLOCK, limit-total+1))
                data = decoder.unconsumed_tail
                total += len(output)
                require(total <= limit, 'decoded byte limit exceeded')
                decoded.update(output)
                write(output)
                require(not decoder.unused_data, 'trailing zlib stream/bytes')
        require(decoder.eof and not decoder.unconsumed_tail, 'truncated zlib stream')
    except zlib.error as error:
        raise ValueError('invalid zlib stream') from error
    require(total == limit and decoded.hexdigest() == wanted, 'decoded size/hash mismatch')
    return {'bytes': packed, 'sha256': compressed.hexdigest()}


def validate_groups(manifest):
    specs = asset_specs(manifest['assets'])
    require(sum(s['bytes'] for s in specs.values()) == size(manifest['assets_total_bytes']),
            'asset total mismatch')
    used, destinations = set(), set()
    for group in manifest['stream_groups'].values():
        names = group['ordered_parts']
        require(isinstance(names, list) and names, 'empty stream group')
        for name in names:
            require(name in specs and name not in used, 'unknown/reused stream part')
            used.add(name)
        require(sum(specs[n]['bytes'] for n in names) == size(group['compressed_bytes']),
                'compressed group byte mismatch')
        size(group['decoded_bytes'])
        digest(group['compressed_sha256']); digest(group['decoded_sha256'])
        name = group['logical_cache_path']
        safe_path(Path('.'), name)
        require(name not in destinations, 'duplicate stream destination')
        destinations.add(name)
    return specs


def payload_bytes(payload):
    require(payload['encoding'] == 'zlib+base64', 'unknown payload encoding')
    require(size(payload['decoded_bytes']) <= PAYLOAD_CAP, 'payload decoded cap')
    try:
        packed = base64.b64decode(payload['data_base64'], validate=True)
    except (ValueError, TypeError) as error:
        raise ValueError('invalid payload base64') from error
    require(len(packed) < ASSET_CAP and base64.b64encode(packed).decode() == payload['data_base64'],
            'payload encoded cap/noncanonical base64')
    require(hashlib.sha256(packed).hexdigest() == digest(payload['compressed_sha256']),
            'payload compressed hash mismatch')
    output = io.BytesIO()
    decode([packed], output.write, payload['decoded_bytes'], payload['sha256'])
    return output.getvalue()


def check_nested_payloads(value):
    if isinstance(value, dict):
        if 'data_base64' in value:
            payload_bytes(value)
            return 1
        return sum(check_nested_payloads(v) for v in value.values())
    if isinstance(value, list):
        return sum(check_nested_payloads(v) for v in value)
    return 0


def verify_native_parts(source, ledger):
    offset = count = 0
    names = set()
    for part in ledger['parts']:
        require(size(part['raw_offset']) == offset and size(part['first_ordinal']) == count,
                'native part order/offset mismatch')
        name = part['logical_path']; safe_path(Path('.'), name)
        require(name not in names, 'duplicate native part path'); names.add(name)
        remaining, sha, rows, last = size(part['bytes']), hashlib.sha256(), 0, b''
        require(remaining > 0 and size(part['row_count']) > 0, 'empty native part')
        while remaining:
            data = source.read(min(BLOCK, remaining))
            require(data, 'truncated native part')
            remaining -= len(data); offset += len(data)
            sha.update(data); rows += data.count(b'\n'); last = data[-1:]
        require(last == b'\n' and rows == part['row_count']
                and sha.hexdigest() == digest(part['sha256']), 'native part row/hash mismatch')
        count += rows
    require(offset == size(ledger['raw_bytes']) and count == size(ledger['rows'])
            and source.read(1) == b'', 'native ledger totals/trailing bytes mismatch')
    return len(names)


def restore(manifest, directory, cache):
    require(manifest['schema'] == 'infantry-contact-custody/v1', 'unknown custody schema')
    require(manifest['asset_cap_bytes'] == ASSET_CAP, 'asset cap changed')
    specs = validate_groups(manifest)
    require(not cache.exists() and not cache.is_symlink(), 'cache must be a new path')
    # Validate every name before creating output; historical source paths stay opaque.
    pngs = manifest['actual_context_PNG_assets']
    singles = [manifest['context_packet_asset']] + manifest['baseline_asset_names']
    mapped = [n for g in manifest['stream_groups'].values() for n in g['ordered_parts']]
    mapped += singles + [p['asset_name'] for p in pngs]
    require(len(mapped) == len(set(mapped)) and set(mapped) == set(specs), 'asset mapping mismatch')
    for p in pngs: safe_path(cache, p['logical_cache_path'])
    prefix = 'https://github.com/'+manifest['repository']+'/releases/download/'+manifest['release_tag']+'/'
    for name, spec in specs.items():
        require(spec['url'] == prefix+name, 'asset repository/tag URL mismatch')
    verify_assets(manifest['assets'], directory)
    cache.mkdir(parents=True)
    packet_name = manifest['context_packet_asset']
    # Context packet decoded size is frozen in its byte-bound measured catalog.
    # The asset hash binds the exact packet; a fixed memory ceiling also bounds its JSON parser.
    raw = bounded_asset(directory/packet_name, PAYLOAD_CAP, specs[packet_name])
    context = json.loads(raw)
    require(context['schema'] == 'infantry-contact-custody-context/v1', 'unknown context schema')
    require(isinstance(context['files'], dict) and len(context['files']) <= 10000, 'invalid context count')
    for name in context['files']: safe_path(cache/'context', name)
    for name, payload in context['files'].items():
        write_new(safe_path(cache/'context', name), payload_bytes(payload))
    baseline_meta = json.loads((cache/'context/proposal-source/measured-response-and-baseline-assets.json').read_bytes())
    baseline_payloads = 0
    for spec in baseline_meta['baseline_assets']:
        name = spec['asset_name']
        require(name in manifest['baseline_asset_names'], 'baseline mapping mismatch')
        require(spec['sha256'] == specs[name]['sha256'] and spec['bytes'] == specs[name]['bytes'],
                'baseline compressed binding mismatch')
        output = safe_path(cache/'baselines', Path(spec['source_file']).name.removesuffix('.zlib'))
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open('xb') as sink:
            decode(verified_blocks(directory, specs[name]), sink.write, spec['decoded_bytes'], spec['decoded_sha256'])
        baseline_payloads += check_nested_payloads(json.loads(output.read_bytes()))
    for name, group in manifest['stream_groups'].items():
        path = safe_path(cache, group['logical_cache_path']); path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('xb') as output:
            actual = decode((data for n in group['ordered_parts'] for data in verified_blocks(directory, specs[n])),
                            output.write, group['decoded_bytes'], group['decoded_sha256'])
        require(actual == {'bytes': group['compressed_bytes'], 'sha256': group['compressed_sha256']},
                'compressed stream group hash mismatch: '+name)
        print(json.dumps({'restored_stream': name, 'decoded_bytes': group['decoded_bytes']}), flush=True)
    for png in pngs:
        path = safe_path(cache, png['logical_cache_path']); path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('xb') as output:
            for data in verified_blocks(directory, specs[png['asset_name']]): output.write(data)
    ledger = json.loads((cache/'context'/manifest['portable_native_ledger_payload']).read_bytes())
    with safe_path(cache, manifest['stream_groups']['native_raw']['logical_cache_path']).open('rb') as source:
        part_count = verify_native_parts(source, ledger)
    require(part_count == manifest['native_raw']['parts'] and ledger['rows'] == manifest['native_raw']['rows'],
            'native part/row totals mismatch')
    result = {'state': 'BYTE_CUSTODY_RESTORED', 'assets': len(specs), 'native_parts': part_count,
              'context_files': len(context['files']), 'baseline_payloads': baseline_payloads,
              'strict_Gram': manifest['strict_Gram'], 'physical_uncertainty': manifest['physical_uncertainty'],
              'E': manifest['E'], 'motion_acceptance': manifest['motion_acceptance'], 'certificate': False}
    write_new(cache/'custody-result.json', (json.dumps(result, indent=2)+'\n').encode())
    return result


def bounded_asset(path, limit, spec):
    """Hash-bound small metadata only; large streams always use decode()."""
    decoder = zlib.decompressobj()
    with path.open('rb') as source:
        packed = source.read(ASSET_CAP)
        require(len(packed) < ASSET_CAP and source.read(1) == b'', 'metadata asset cap')
    require(len(packed) == spec['bytes'] and hashlib.sha256(packed).hexdigest() == spec['sha256'],
            'metadata asset changed')
    try:
        raw = decoder.decompress(packed, limit+1)
    except zlib.error as error:
        raise ValueError('invalid metadata zlib') from error
    require(len(raw) <= limit and decoder.eof and not decoder.unused_data
            and not decoder.unconsumed_tail, 'metadata zlib cap/trailing/truncation')
    return raw


def receipt_parts(manifest, cache):
    root = cache/'context/run/native-execution'
    plan = json.loads((root/'native-job-plan.json').read_bytes())
    ledger = json.loads((cache/'context'/manifest['portable_native_ledger_payload']).read_bytes())
    require(len(plan['jobs']) == manifest['C_response_transport']['context_count'], 'native context count mismatch')
    parts = []
    for index, job in enumerate(plan['jobs']):
        require(type(job['index']) is int and job['index'] == index, 'native job order mismatch')
        directory = root/'jobs'/f'job{index:05d}'
        raw = (directory/'parts.jsonl').read_bytes()
        require(hashlib.sha256(raw).hexdigest() == job['parts_sha256'], 'original parts manifest hash mismatch')
        originals = [json.loads(line) for line in raw.splitlines()]
        receipts = [json.loads(line) for line in (directory/'receipts.jsonl').read_bytes().splitlines()]
        require(len(originals) == len(receipts) == job['part_count'], 'original receipt part count mismatch')
        for original, receipt in zip(originals, receipts):
            require(all(receipt[k] == v for k, v in original.items()), 'original receipt identity mismatch')
            require(len(parts) < len(ledger['parts']), 'extra original receipt')
            part = ledger['parts'][len(parts)]
            require(receipt['response_sha256'] == part['sha256']
                    and receipt['first_ordinal'] == part['first_ordinal']
                    and receipt['row_count'] == part['row_count'], 'original receipt/native part mismatch')
            parts.append(original)
    require(len(parts) == len(ledger['parts']), 'missing original receipts')
    return parts


def check_request_chunk(chunk, index, spec):
    require(chunk['chunk_index'] == index and chunk['first_ordinal'] == spec['first_ordinal']
            and chunk['row_count'] == spec['row_count'] and chunk['sha256'] == spec['request_sha256'],
            'original request chunk/receipt mismatch')


class ReceiptReader:
    """Tap original chunk identity while QueryStream validates every decoded byte/row."""
    def __init__(self, source, parts):
        self.source, self.parts, self.index = source, parts, 0

    def readline(self, limit):
        line = self.source.readline(limit)
        if line.startswith((b'{"chunk_index":', b',{"chunk_index":')):
            require(self.index < len(self.parts), 'extra request chunk')
            check_request_chunk(json.loads(line.lstrip(b',')), self.index, self.parts[self.index])
            self.index += 1
        return line

    def read(self, limit):
        return self.source.read(limit)


def replay(manifest, cache, kind):
    import pivot_metrics as metric
    group_name = 'original_requests' if kind == 'requests' else 'responses'
    path = safe_path(cache, manifest['stream_groups'][group_name]['logical_cache_path'])
    result_path = cache/('replay-'+kind+'.json')
    require(not result_path.exists(), 'replay result already exists; preserve previous attempt')
    frozen = json.loads((cache/'context'/manifest['frozen_source_manifest_payload']).read_bytes())
    parts = receipt_parts(manifest, cache)
    counts = {'vertex': 0, 'anchor': 0}
    native = None
    if kind == 'native':
        native = safe_path(cache, manifest['stream_groups']['native_raw']['logical_cache_path']).open('rb')
    try:
        with path.open('rb') as source:
            first = source.readline(metric.STREAM_LINE+1)
            require(len(first) <= metric.STREAM_LINE, 'query header exceeds cap')
            header = metric.decode_raw_observation(first[:-2]+b'}')['header']
            source.seek(0)
            wire_kind = 'requests' if kind == 'requests' else 'responses'
            tapped = ReceiptReader(source, parts) if kind == 'requests' else source
            stream = metric.QueryStream(tapped, wire_kind, header)
            request_sha = hashlib.sha256()
            count = 0
            for row in stream:
                request = row if kind == 'requests' else row['request']
                require(request['role'] in counts, 'unknown request role')
                counts[request['role']] += 1; count += 1
                if native is not None:
                    raw = native.readline(metric.STREAM_LINE+1)
                    require(raw.endswith(b'\n') and len(raw) <= metric.STREAM_LINE, 'native row cap/truncation')
                    observed = metric.decode_raw_observation(raw)
                    request_bytes = observed['request_utf8'].encode('utf-8')
                    require(hashlib.sha256(request_bytes).hexdigest() == observed['request_sha256'],
                            'native request UTF8 hash mismatch')
                    require(request_bytes == metric.compact(request), 'original native request bytes mismatch')
                    require(dict(observed['response'], request=request) == row, 'native response words mismatch')
                    request_sha.update(request_bytes+b'\n')
            if native is not None:
                require(native.read(1) == b'', 'extra native rows')
                require(request_sha.hexdigest() == manifest['C_response_transport']['request_stream_sha256'],
                        'native original request stream digest mismatch')
            expected = manifest['stream_groups'][group_name]
            require(stream.file_sha256 == expected['decoded_sha256'], 'query whole file hash mismatch')
            require(count == manifest['C_response_transport']['rows'], 'query count mismatch')
            require(counts == {'vertex': frozen['required_vertex_rows'], 'anchor': frozen['required_anchor_rows']},
                    'vertex/anchor count mismatch')
            if kind == 'requests':
                require(tapped.index == len(parts), 'missing original request chunks')
                require(stream.footer['stream_sha256'] == manifest['original_request_file']['canonical_request_rowstream_sha256'],
                        'request canonical digest mismatch')
            else:
                require(stream.footer == manifest['C_response_transport']['footer'], 'response footer mismatch')
                require(header['request_stream_sha256'] == manifest['C_response_transport']['request_stream_sha256'],
                        'response request binding mismatch')
            result = {'state': 'TRANSPORT_REPLAY_ONLY', 'kind': kind, 'counts': counts,
                      'footer': stream.footer, 'file_sha256': stream.file_sha256,
                      'physical_acceptance': False, 'certificate': False}
            write_new(result_path, (json.dumps(result, indent=2)+'\n').encode())
            return result
    finally:
        if native is not None: native.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['restore', 'replay'])
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--assets', type=Path)
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--kind', choices=['requests', 'responses', 'native'])
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_bytes())
    if args.operation == 'restore':
        parser.error('--assets required for restore') if args.assets is None else None
        result = restore(manifest, args.assets, args.cache)
    else:
        parser.error('--kind required for replay') if args.kind is None else None
        result = replay(manifest, args.cache, args.kind)
    print(json.dumps(result), flush=True)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        sys.exit(str(error))
