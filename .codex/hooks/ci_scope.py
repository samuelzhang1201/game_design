"""Harness-only PRs validate the harness without starting the game suite."""
import subprocess
import sys
from fnmatch import fnmatchcase


def needs_game_tests(paths):
    for path in paths:
        if path == 'RANDOM_EVENTS.md' or path.startswith('game_story/'):
            return True
        if path.endswith('.md') or any(fnmatchcase(path, glob) for glob in
                ['.codex/*', '.github/pull_request_template.md', '.github/workflows/tests.yml']):
            continue
        return True
    return False


if __name__ == '__main__':
    paths = subprocess.check_output(['git', 'diff', '--name-only', '-z', sys.argv[1], 'HEAD']).decode().split('\0')
    print('true' if needs_game_tests([p for p in paths if p]) else 'false')
