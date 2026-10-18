"""Exercise the real shell runner's gates without importing the art tree."""
import os
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest


class RunnerTests(unittest.TestCase):
    def run_runner(self, mode='success', args=None, empty_catalog=False):
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp, 'godot')
            fake.write_text('''#!/usr/bin/env python3
import os, sys, time
assert os.environ['CC_FORCE_OFFLINE'] == '1'
mode = os.environ['FAKE_MODE']
if '--import' in sys.argv:
    sys.exit(7 if mode == 'import-failure' else 0)
assert any(a.startswith('-gtest=res://tests/') for a in sys.argv)
if mode == 'timeout': time.sleep(10)
print('Scripts 0' if mode == 'count' else 'Scripts 1')
if mode == 'ignored': print('Ignoring script broken.gd')
if mode == 'runtime': print('SCRIPT ERROR: bad call\\n    at: run (res://scripts/broken.gd:1)')
if mode == 'errors': print('Errors 1')
sys.exit(3 if mode == 'failure' else 0)
''')
            fake.chmod(0o755)
            runner_root = Path.cwd()
            if empty_catalog:
                runner_root = Path(tmp)
                for name in ['run_tests.sh', 'tools/select_gut_tests.py', 'tests/categories.json']:
                    target = runner_root / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(name, target)
            return subprocess.run(['./run_tests.sh', *(args or ['--test', 'tests/engine/test_calendar.gd'])],
                env={**os.environ, 'GODOT': str(fake), 'FAKE_MODE': mode,
                     'TEST_TIMEOUT_SECONDS': '1' if mode == 'timeout' else '10'},
                cwd=runner_root, text=True, capture_output=True)

    def test_success_and_explicit_script_count(self):
        self.assertEqual(self.run_runner().returncode, 0)

    def test_no_selection_starts_no_godot(self):
        result = self.run_runner('import-failure', ['--category', 'engine-core'], empty_catalog=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn('Godot not started', result.stdout)

    def test_existing_failure_gates_survive_selection(self):
        for mode, message in [('ignored', 'GUT ignored'), ('runtime', 'SCRIPT ERROR outside'),
                              ('count', 'selected test scripts'), ('errors', 'Unexpected error count'),
                              ('failure', 'GUT exited with code 3'), ('import-failure', 'import failed')]:
            with self.subTest(mode=mode):
                result = self.run_runner(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stdout + result.stderr)

    def test_deadline_still_propagates_and_preserves_output(self):
        result = self.run_runner('timeout')
        self.assertEqual(result.returncode, 124)
        self.assertIn('output preserved', result.stderr)
        path = result.stderr.split('output preserved at ')[-1].strip()
        Path(path).unlink()

    def test_unknown_option_and_missing_script_fail_before_import(self):
        for args in [['--shrad=1/8'], ['--test', 'tests/engine/test_deleted.gd']]:
            self.assertNotEqual(self.run_runner(args=args).returncode, 0)


if __name__ == '__main__':
    unittest.main()
