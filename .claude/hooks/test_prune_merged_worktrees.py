"""Checks for the merged-worktree pruner: unit rules plus one real git worktree."""
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import prune_merged_worktrees as p

M = {"abc"}
OLD = p.IDLE_SECONDS + 1


class KeepReason(unittest.TestCase):
    def test_merged_clean_idle_goes(self):
        self.assertIsNone(p.keep_reason("abc", M, [], [".godot/", "x/.DS_Store"], OLD, False, False))

    def test_unmerged_head_stays(self):
        self.assertIn("not a merged", p.keep_reason("def", M, [], [], OLD, False, False))

    def test_dirty_stays(self):
        self.assertIn("uncommitted", p.keep_reason("abc", M, [" M a.gd"], [], OLD, False, False))

    def test_ignored_art_stays(self):
        r = p.keep_reason("abc", M, [], ["assets/3D/units/x/model_wip/"], OLD, False, False)
        self.assertIn("model_wip", r)

    def test_recent_locked_self_stay(self):
        self.assertIn("active", p.keep_reason("abc", M, [], [], 60, False, False))
        self.assertEqual(p.keep_reason("abc", M, [], [], OLD, True, False), "locked")
        self.assertIn("this session", p.keep_reason("abc", M, [], [], OLD, False, True))


class RealWorktree(unittest.TestCase):
    def test_parses_porcelain(self):
        with tempfile.TemporaryDirectory() as d:
            repo, wt = Path(d) / "r", Path(d) / "w"
            run = lambda *a, cwd=repo: subprocess.run(a, cwd=cwd, check=True, capture_output=True)
            repo.mkdir()
            run("git", "init", "-q")
            run("git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "x")
            run("git", "worktree", "add", "-q", "-b", "b", str(wt))
            cwd = os.getcwd()
            os.chdir(repo)
            try:
                wts = p.worktrees()
            finally:
                os.chdir(cwd)
            self.assertEqual(len(wts), 2)
            self.assertEqual(Path(wts[1]["worktree"]).resolve(), wt.resolve())
            self.assertEqual(wts[1]["branch"], "refs/heads/b")
            self.assertEqual(len(wts[1]["HEAD"]), 40)


if __name__ == "__main__":
    unittest.main()
