#!/usr/bin/env python3
"""Select functional GUT categories; expensive content requires an explicit request."""
import argparse
from fnmatch import fnmatchcase
import json
import re
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = json.loads((ROOT / 'tests/categories.json').read_text())
CATEGORIES = MANIFEST['categories']


def matches(path, patterns):
    return any(fnmatchcase(path, pattern) for pattern in patterns)


def category_of(path):
    for name, config in CATEGORIES.items():
        if matches(path, config['patterns']):
            return name
    raise ValueError(f'Unclassified GUT script: {path}; add a content category in tests/categories.json')


def functional_categories():
    return [name for name, config in CATEGORIES.items() if not config.get('opt_in')]


def catalog():
    groups = {name: [] for name in CATEGORIES}
    for path in sorted(ROOT.glob('tests/**/test_*.gd')):
        relative = path.relative_to(ROOT).as_posix()
        groups[category_of(relative)].append(relative)
    return groups


def changed_paths(base, cwd=ROOT):
    # --no-renames represents a rename as delete + add, preserving BOTH routing scopes.
    raw = subprocess.check_output(['git', 'diff', '--name-only', '--no-renames', '-z', base, '--'], cwd=cwd)
    return [path for path in raw.decode().split('\0') if path]


def result(categories, groups):
    names = sorted(name for name in categories if groups[name])
    files = sorted({path for name in names for path in groups[name]})
    return {'categories': names, 'files': files, 'matrix': {'category': names}, 'run_gut': bool(files)}


def select(paths, groups, include=()):
    selected = set(include)
    functional = set(functional_categories())
    for path in paths:
        if path.startswith('tests/') and (path.endswith('.gd') or path.endswith('.gd.uid')) and Path(path.removesuffix('.uid')).name.startswith('test_'):
            try:
                category = category_of(path.removesuffix('.uid'))
            except ValueError:
                selected.update(functional)
            else:
                if category in functional:
                    selected.add(category)
            continue
        # Runtime prose is data, even though it uses Markdown.
        if path == 'RANDOM_EVENTS.md' or path.startswith(('game_story/', 'data/', 'tests/')):
            selected.update(functional)
        elif path == '.github/workflows/tests.yml' or path == 'run_tests.sh' or path.startswith(('tools/select_gut_tests', 'tools/test_select_gut_tests', 'tools/test_run_tests', 'tools/run_with_timeout', 'tools/test_run_with_timeout')):
            selected.update(functional)
        elif path.endswith('.md') or path.startswith('.codex/') or path == '.github/pull_request_template.md':
            continue
        else:
            for route in MANIFEST['routes']:
                if matches(path, route['patterns']):
                    selected.update(route['categories'])
                    break
            else:
                # Shared engine/data/assets and unknown runtime changes can reach every consumer.
                selected.update(functional)
    return result(selected, groups)


def requested_categories(text):
    names = []
    for line in re.findall(r'^GUT_INCLUDE:[ \t]*(.*)$', text, re.MULTILINE):
        names.extend(name.strip() for name in line.split(',') if name.strip())
    unknown = set(names) - set(CATEGORIES)
    if unknown:
        raise ValueError(f'Unknown GUT categories: {sorted(unknown)}')
    return names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    scope = parser.add_mutually_exclusive_group()
    scope.add_argument('--functional', action='store_true', help='All functional categories (manual runs).')
    scope.add_argument('--base', help='Compare this Git revision with the current worktree (includes deletions).')
    parser.add_argument('--include', action='append', choices=CATEGORIES, default=[], help='Explicit plan/PR/manual category request, including expensive suites.')
    parser.add_argument('--category', action='append', choices=CATEGORIES, default=[], help='Run exactly this explicitly requested category.')
    parser.add_argument('--test', action='append', default=[], help='Run exactly this explicitly requested test script.')
    parser.add_argument('--format', choices=['json', 'files'], default='json')
    parser.add_argument('--request-text', default='', help='PR body containing a GUT_INCLUDE: category,... line.')
    parser.add_argument('--github-output', type=Path, help='Write the CI matrix and run-gut decision here.')
    args = parser.parse_args()
    args.include.extend(requested_categories(args.request_text))
    groups = catalog()
    if args.category or args.test:
        if args.base or args.functional or args.include:
            parser.error('--category/--test cannot be mixed with --base/--include')
        chosen = result(args.category, groups)
        for path in args.test:
            if path not in groups[category_of(path)]:
                parser.error(f'Missing test script: {path}')
        chosen['files'] = sorted(set(chosen['files']) | set(args.test))
        chosen['run_gut'] = bool(chosen['files'])
    else:
        chosen = select(['project.godot'] if args.functional else changed_paths(args.base or 'origin/main'), groups, args.include)
    if args.github_output:
        with args.github_output.open('a') as output:
            output.write(f"run-gut={str(chosen['run_gut']).lower()}\n")
            output.write(f"matrix={json.dumps(chosen['matrix'])}\n")
    print(json.dumps(chosen) if args.format == 'json' else '\n'.join(chosen['files']))


if __name__ == '__main__':
    main()
