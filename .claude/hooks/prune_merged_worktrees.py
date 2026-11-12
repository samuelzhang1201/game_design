"""Remove git worktrees whose work has been merged into main.

A worktree goes only when ALL hold:
  - its HEAD is exactly the head commit of a merged PR (so it holds nothing
    that main lacks; a fresh branch cut from main never matches),
  - `git status` is clean (no changes, no untracked files),
  - it holds no git-ignored files besides IGNORED_OK (a git-ignored
    `model_wip/` source would be lost),
  - it is not locked, not this session's checkout, and its git admin dir has
    been idle for IDLE_SECONDS (a session may still be reading it).
Branches are kept: a resumed session checks its branch out again.

Run by the SessionStart hook in `.claude/settings.json` in the background.
`--dry-run` lists what would go and why the rest stay. Log: <git-common-dir>/prune-merged-worktrees.log
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

IDLE_SECONDS = 3600
IGNORED_OK = (".godot/", ".import/", "__pycache__/", ".DS_Store")


def git(*args: str, cwd: str | None = None) -> str:
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, check=True).stdout


def worktrees() -> list[dict]:
    """`git worktree list --porcelain` as dicts; the first entry is the main checkout."""
    out, cur = [], {}
    for line in git("worktree", "list", "--porcelain").splitlines() + [""]:
        if not line:
            if cur:
                out.append(cur)
            cur = {}
            continue
        key, _, val = line.partition(" ")
        cur[key] = val or True
    return out


def blocked_ignored(ignored: list[str]) -> list[str]:
    return [p for p in ignored if not any(p == ok or p.startswith(ok) or p.endswith("/" + ok) or ("/" + ok) in p for ok in IGNORED_OK)]


def keep_reason(head: str, merged: set[str], status: list[str], ignored: list[str], idle: float, locked: bool, is_self: bool) -> str | None:
    """None = removable, else why it stays."""
    if is_self:
        return "this session's checkout"
    if locked:
        return "locked"
    if head not in merged:
        return "HEAD is not a merged PR head"
    if status:
        return f"{len(status)} uncommitted/untracked paths"
    bad = blocked_ignored(ignored)
    if bad:
        return f"git-ignored files would be lost: {', '.join(bad[:3])}"
    if idle < IDLE_SECONDS:
        return f"active {int(idle // 60)} min ago"
    return None


def main() -> int:
    dry = "--dry-run" in sys.argv
    common = Path(git("rev-parse", "--git-common-dir").strip()).resolve()
    lock = common / "prune-merged-worktrees.lock"
    try:
        lock.mkdir()
    except FileExistsError:
        if time.time() - lock.stat().st_mtime < 600:
            return 0  # another session is pruning
    try:
        try:
            prs = subprocess.run(
                ["gh", "pr", "list", "--state", "merged", "--limit", "1000", "--json", "headRefOid"],
                capture_output=True, text=True, check=True, timeout=60,
            ).stdout
        except (OSError, subprocess.SubprocessError):
            return 0  # offline or no gh: remove nothing
        merged = {p["headRefOid"] for p in json.loads(prs)}
        here = {str(Path(p).resolve()) for p in (os.getcwd(), os.environ.get("CLAUDE_PROJECT_DIR", "")) if p}
        log = []
        for wt in worktrees()[1:]:
            path = wt["worktree"]
            if wt.get("prunable") or not Path(path).is_dir():
                continue
            admin = Path(git("rev-parse", "--absolute-git-dir", cwd=path).strip())
            idle = time.time() - max((admin / f).stat().st_mtime for f in ("HEAD", "index", "logs/HEAD") if (admin / f).exists())
            lines = git("status", "--porcelain", "--ignored", cwd=path).splitlines()
            reason = keep_reason(
                wt.get("HEAD", ""), merged,
                [l for l in lines if not l.startswith("!!")],
                [l[3:] for l in lines if l.startswith("!!")],
                idle, "locked" in wt, str(Path(path).resolve()) in here,
            )
            if reason:
                if dry:
                    print(f"keep   {path}: {reason}")
                continue
            if dry:
                print(f"REMOVE {path} ({wt.get('branch', 'detached')})")
                continue
            try:
                git("worktree", "remove", path)
                log.append(f"{time.strftime('%Y-%m-%d %H:%M')} removed {path} {wt.get('branch', 'detached')}")
            except subprocess.CalledProcessError as e:
                log.append(f"{time.strftime('%Y-%m-%d %H:%M')} failed {path}: {e.stderr.strip()}")
        if log:
            with open(common / "prune-merged-worktrees.log", "a") as f:
                f.write("\n".join(log) + "\n")
    finally:
        lock.rmdir()
    return 0


if __name__ == "__main__":
    sys.exit(main())
