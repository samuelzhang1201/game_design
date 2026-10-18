"""Real subprocess checks for the test runner's deadline and cleanup."""
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time
import unittest


RUNNER = Path(__file__).with_name("run_with_timeout.py")


class DeadlineTests(unittest.TestCase):
    def run_command(self, code, seconds="1"):
        return subprocess.run(
            [sys.executable, str(RUNNER), seconds, sys.executable, "-c", code],
            capture_output=True, text=True, timeout=10,
        )

    def test_preserves_output_and_exit_code(self):
        result = self.run_command("print('diagnostic', flush=True); raise SystemExit(7)")
        self.assertEqual(result.returncode, 7)
        self.assertIn("diagnostic", result.stdout)

    def test_timeout_kills_descendants_that_ignore_term(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "leaked"
            child = ("import signal,time; from pathlib import Path; "
                     "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                     f"time.sleep(2); Path({str(marker)!r}).touch()")
            code = ("import subprocess,sys,time; "
                    f"subprocess.Popen([sys.executable, '-c', {child!r}]); "
                    "print('last test', flush=True); time.sleep(60)")
            result = self.run_command(code)
            self.assertEqual(result.returncode, 124)
            self.assertIn("last test", result.stdout)
            self.assertIn("timed out", result.stderr)
            time.sleep(2.5)
            self.assertFalse(marker.exists(), "a descendant survived the deadline")

    def test_term_stops_the_child(self):
        with tempfile.TemporaryDirectory() as directory:
            pid_file = Path(directory) / "pid"
            code = ("import os,time; from pathlib import Path; "
                    f"Path({str(pid_file)!r}).write_text(str(os.getpid())); time.sleep(60)")
            proc = subprocess.Popen([sys.executable, str(RUNNER), "30", sys.executable, "-c", code])
            try:
                limit = time.monotonic() + 5
                while not pid_file.exists() and time.monotonic() < limit:
                    time.sleep(0.02)
                self.assertTrue(pid_file.exists())
                proc.send_signal(signal.SIGTERM)
                self.assertEqual(proc.wait(timeout=5), 143)
                with self.assertRaises(ProcessLookupError):
                    os.kill(int(pid_file.read_text()), 0)
            finally:
                if proc.poll() is None:
                    proc.kill()
                    proc.wait()

    def test_rejects_invalid_deadlines(self):
        for seconds in ["0", "-1", "no", "nan", "inf"]:
            with self.subTest(seconds=seconds):
                self.assertEqual(self.run_command("pass", seconds).returncode, 2)

    def test_shell_runner_bounds_import_and_test_and_preserves_log(self):
        for phase in ["import", "tests"]:
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / "tools").symlink_to(RUNNER.parent)
                godot = root / "godot"
                godot.write_text(
                    f"#!{sys.executable}\nimport sys,time\n"
                    f"if ('--import' in sys.argv) == {phase == 'import'}:\n"
                    "    print('stalled phase', flush=True)\n    time.sleep(60)\n"
                )
                godot.chmod(0o755)
                result = subprocess.run(
                    ["sh", str(RUNNER.parent.parent / "run_tests.sh"), "--fast"],
                    cwd=root, env={**os.environ, "GODOT": str(godot), "TEST_TIMEOUT_SECONDS": "1"},
                    capture_output=True, text=True, timeout=10,
                )
                self.assertEqual(result.returncode, 124)
                self.assertIn("stalled phase", result.stdout)
                if phase == "tests":
                    match = re.search(r"output preserved at (\S+)", result.stderr)
                    self.assertIsNotNone(match)
                    log = Path(match.group(1))
                    try:
                        self.assertIn("timed out", log.read_text())
                    finally:
                        log.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
