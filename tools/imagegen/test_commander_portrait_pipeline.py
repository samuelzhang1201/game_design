"""Offline regressions for three-digit cast IDs and approved source selection."""
import importlib.util
import hashlib
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ART = Path(__file__).resolve().parents[2] / 'assets/imagegen'
sys.path.insert(0, str(ART))
import generate
import post


def installer():
    spec = importlib.util.spec_from_file_location('cast_installer', ART / 'install_map_art.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CommanderPortraitPipelineTests(unittest.TestCase):
    def test_library_keeps_three_digit_character_id(self):
        text = '#### `K-100` Person\n\n**外貌**：`grey-haired woman`\n\n```\n[S], portrait, [C-FULL]\n```\n'
        row, = generate.parse_library(text)
        self.assertEqual(row['id'], 'K-100')
        self.assertEqual(row['appearance'], 'grey-haired woman')

    def test_post_does_not_truncate_three_digit_output_id(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            def download(_image, dest):
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(b'cutout')
            with patch.object(post, 'OUT_DIR', out), patch.object(post, 'upload', return_value='source.png'), \
                 patch.object(post.gen, '_post', return_value={'prompt_id': 'job'}), \
                 patch.object(post.gen, 'wait_for', return_value=[{}]), patch.object(post.gen, 'download', download), \
                 patch.object(sys, 'argv', ['post', '--tier', 'chip', 'K-100-full_c-bust.png']):
                self.assertEqual(post.main(), 0)
            self.assertEqual((out / 'chip/K-100.png').read_bytes(), b'cutout')
            self.assertFalse((out / 'chip/K-10.png').exists())

    def test_derived_chip_preserves_reviewed_rgba_crop_without_a_new_model(self):
        module = installer()
        with tempfile.TemporaryDirectory() as folder:
            source, target = Path(folder) / 'full.png', Path(folder) / 'chip.png'
            pixels = bytes([10, 20, 30, 0, 100, 110, 120, 255,
                            30, 40, 50, 0, 140, 150, 160, 255])
            post.encode_png(source, 2, 2, 4, pixels)
            module.derive_cast_chip(source, [4, 4], [2, 0, 2, 4], target, 1)
            self.assertEqual(post.decode_png(target), (1, 1, 4, bytearray([120, 130, 140, 255])))

    def test_pending_or_changed_commander_source_fails_closed(self):
        module = installer()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            module.ROOT, module.HERE = root, root / 'imagegen'
            (module.HERE / 'out/cast').mkdir(parents=True)
            (module.HERE / 'cast_art.csv').write_text('character_id,art_id,seed,notes,requires_review\npending,K-100,1,planned,1\n')
            for tag in ['c-full', 'c-bust']:
                (module.HERE / 'out/cast' / f'K-100_person_{tag}_s1.png').write_bytes(b'unreviewed')
            with patch.object(module.subprocess, 'run') as run, patch.object(sys, 'argv', ['install_map_art', 'cast']):
                self.assertEqual(module.main(), 0)
                run.assert_not_called()
            self.assertFalse((root / 'assets/2D/portraits/cast/pending.png').exists())
            self.assertFalse((root / 'assets/2D/portraits/cast/full/pending.png').exists())
            records = [dict(art_id='K-100', tier=tier, review_status='approved',
                            source=f'imagegen/out/cast/K-100_person_{tag}_s1.png',
                            sha256='wrong-source-hash', output_sha256='reviewed-output-hash')
                       for tier, tag in [('chip', 'c-bust'), ('full', 'c-full')]]
            (module.HERE / 'commander_portrait_reviews.json').write_text(json.dumps(dict(records=records)))
            with patch.object(module.subprocess, 'run') as run, patch.object(sys, 'argv', ['install_map_art', 'cast']):
                self.assertEqual(module.main(), 0)
                run.assert_not_called()
            self.assertFalse((root / 'assets/2D/portraits/cast/pending.png').exists())
            self.assertFalse((root / 'assets/2D/portraits/cast/full/pending.png').exists())

    def test_installer_uses_approved_tier_sources_and_exact_cutout_ids(self):
        module = installer()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            module.ROOT, module.HERE = root, root / 'imagegen'
            (module.HERE / 'out/cast').mkdir(parents=True)
            (root / 'approved').mkdir()
            (module.HERE / 'cast_art.csv').write_text('character_id,art_id,seed,notes,requires_review\nnew,K-100,qwen2512desk4_s7,,1\nlegacy,K-10,1,,0\n')
            records = []
            for tier, tag in [('chip', 'c-bust'), ('full', 'c-full')]:
                source = root / 'approved' / f'K-100_{tier}.png'
                source.write_bytes(f'approved-{tier}'.encode())
                records.append(dict(art_id='K-100', tier=tier, review_status='approved_and_installed', source=str(source.relative_to(root)), sha256=hashlib.sha256(source.read_bytes()).hexdigest(), installed_sha256=hashlib.sha256(source.read_bytes()).hexdigest()))
                (module.HERE / 'out/cast' / f'K-10_legacy_{tag}_s1.png').write_bytes(f'legacy-{tier}'.encode())
                staged = module.HERE / 'out/game' / tier
                staged.mkdir(parents=True)
                (staged / 'K-109.png').write_bytes(b'wrong-person')
            records.append(dict(art_id='K-100', tier='chip', review_status='rejected', source='wrong.png'))
            (module.HERE / 'commander_portrait_reviews.json').write_text(json.dumps(dict(records=records)))
            def cutout(args, **_kwargs):
                tier, source = args[args.index('--tier') + 1], Path(args[-1])
                art_id = re.match(r'K-\d+', source.name).group()
                (module.HERE / 'out/game' / tier / (art_id + '.png')).write_bytes(source.read_bytes())
                return SimpleNamespace(returncode=0)
            with patch.object(module.subprocess, 'run', cutout):
                self.assertEqual(module.install_cast(), 4)
            for tier, sub in [('chip', ''), ('full', 'full/')]:
                dest = root / f'assets/2D/portraits/cast/{sub}'
                self.assertEqual((dest / 'new.png').read_bytes(), f'approved-{tier}'.encode())
                self.assertEqual((dest / 'legacy.png').read_bytes(), f'legacy-{tier}'.encode())


if __name__ == '__main__':
    unittest.main()
