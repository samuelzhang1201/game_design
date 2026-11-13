#!/usr/bin/env python3
"""The product gate on PR bodies, run by `harness-checks` (`python3 tools/check_pr_gate.py`).

A `codex/` or `claude/` PR declares `prd_step`, `player_outcome` and `wired` as standalone body lines, and a
`claude/` PR that would be the sixth unwired one in a row also needs an `owner_approval:` line. See the product
gate in cicd_procedure.md. A `claude/` PR that changes more than `MAX_SUBSYSTEMS` folders under
`scripts/` also needs a `scope_reason:` line (one step, one PR).
The environment supplies PR_BODY, PR_BRANCH, PR_NUMBER, BASE_SHA (and GH_TOKEN for `gh`)."""
import json
import os
import re
import subprocess
import sys

PRD_STEP = re.compile(r'Step (10|[1-9])|BG-[1-6]|CS-[1-5]\.[1-5]|EV-[1-4]|CH-[1-5]|FS-[1-4]|RD-[1-3]|EC-[1-3]|AR-[1-4]|L0|M[1-6]|harness')
DECLARED_PRODUCT_FIELDS = ('prd_step', 'player_outcome', 'wired')
MAX_UNWIRED_BACKLOG = 5
HARNESS_PATHS = ('.gitignore', '.superpowers/session-handovers', '.claude/agents', '.claude/hooks', '.claude/settings.json', '.github',
                 'AGENTS.md', 'CLAUDE.md', 'cicd_procedure.md', 'run_tests.sh',
                 'tests/categories.json', 'tools/select_gut_tests.py', 'tools/test_select_gut_tests.py',
                 'tools/run_with_timeout.py', 'tools/test_run_with_timeout.py', 'tools/test_run_tests.py',
                 'tools/check_pr_gate.py', 'tools/test_check_pr_gate.py')
# The first PR checked on each branch prefix; earlier PRs finish under their existing declaration.
FIRST_CHECKED_PR = {'codex/': 279, 'claude/': 294}
MAX_SUBSYSTEMS = 2
FIRST_SCOPE_CHECKED_PR = 306


def is_harness_file(name):
    return any(name == path or name.startswith(path + '/') for path in HARNESS_PATHS)


def pr_body_problems(body, branch, number, files):
    """A Codex or Claude Code PR declares what it does for the MVP, so CI covers work that never went through dispatch."""
    first = next((n for prefix, n in FIRST_CHECKED_PR.items() if branch.startswith(prefix)), None)
    if first is None or number < first:
        return []
    fields, problems = {}, []
    for name in DECLARED_PRODUCT_FIELDS:
        values = re.findall(r'^(?:- )?' + name + r':[ \t]*(.*?)[ \t\r]*$', body, re.M)
        if len(values) != 1 or not values[0]:
            problems.append(f'PR body needs exactly one non-empty "{name}: ..." line')
        else:
            fields[name] = values[0]
    prd_step, wired = fields.get('prd_step'), fields.get('wired')
    if prd_step is not None and not PRD_STEP.fullmatch(prd_step):
        problems.append(f'prd_step "{prd_step}" names no PRD step or harness')
    if wired is not None and wired not in ('true', 'false'):
        problems.append(f'wired must be true or false, not "{wired}"')
    if prd_step == 'harness':
        if wired == 'true':
            problems.append('a harness PR has wired: false')
        problems += [f'prd_step harness cannot change {name}' for name in files if not is_harness_file(name)]
    return problems


def declared_fields(body):
    """The product fields a PR body declares, or None when it declares none (older PRs)."""
    found = {}
    for name in ('prd_step', 'wired', 'owner_approval'):
        values = re.findall(r'^(?:- )?' + name + r':[ \t]*(.*?)[ \t\r]*$', body or '', re.M)
        found[name] = values[0] if values else ''
    return found if found['prd_step'] and found['wired'] else None


def unwired_since_gate(history):
    """Merged unwired PRs, newest first, since the last owner approval or merged player-reachable PR.

    Harness PRs and PRs that declare nothing neither count nor reset, like harness steps in unwired_backlog."""
    count = 0
    for body in history:
        fields = declared_fields(body)
        if fields is None or fields['prd_step'] == 'harness':
            continue
        if fields['owner_approval'] or fields['wired'] == 'true':
            break
        count += 1
    return count


def backlog_problems(history, body, branch, number):
    """A `claude/` PR that would be the sixth unwired one in a row waits for the owner.

    `history` is a callable returning merged PR bodies newest first, called only when the limit can bind."""
    if not branch.startswith('claude/') or number < FIRST_CHECKED_PR['claude/']:
        return []
    fields = declared_fields(body)
    if fields is None or fields['prd_step'] == 'harness' or fields['wired'] != 'false':
        return []
    approval = fields['owner_approval']
    if approval:
        if not re.search(r'(?<![\w#-])#' + str(number) + r'(?!\w)|(?<![\w-])' + re.escape(branch) + r'(?![\w-])', approval):
            return [f'owner_approval must name this PR (#{number}) or its branch; a blanket authorization does not count']
        return []
    backlog = unwired_since_gate(history()) + 1
    if backlog > MAX_UNWIRED_BACKLOG:
        return [f'this PR would make {backlog} unwired PRs since the last merged wired PR or owner approval (limit '
                f'{MAX_UNWIRED_BACKLOG}). Stop and ask the owner; only an "owner_approval: <the owner\'s words naming '
                f'#{number}>" body line continues the chain.']
    return []


def scope_problems(body, branch, number, files):
    """A `claude/` PR touching more than MAX_SUBSYSTEMS `scripts/<name>/` folders says why in a `scope_reason:` line."""
    if not branch.startswith('claude/') or number < FIRST_SCOPE_CHECKED_PR:
        return []
    subsystems = sorted({name.split('/')[1] for name in files if name.startswith('scripts/') and name.count('/') >= 2})
    if len(subsystems) <= MAX_SUBSYSTEMS or re.search(r'^(?:- )?scope_reason:[ \t]*\S', body, re.M):
        return []
    return [f'this PR changes {len(subsystems)} subsystems under scripts/ ({", ".join(subsystems)}; limit {MAX_SUBSYSTEMS}). '
            'Split it into one PR per step, or add a "scope_reason: <why this is one step>" body line.']


def merged_bodies():
    """Bodies of the latest merged PRs on main, newest first (needs `gh` and GH_TOKEN, as in CI)."""
    out = subprocess.run(['gh', 'pr', 'list', '--state', 'merged', '--base', 'main', '--limit', '60',
                          '--json', 'body,mergedAt'], capture_output=True, text=True, check=True, timeout=60).stdout
    return [pr['body'] or '' for pr in sorted(json.loads(out), key=lambda pr: pr['mergedAt'], reverse=True)]


def check_pr():
    """`--check-pr`: the CI gate, reading the PR from the environment and its diff from Git."""
    diff = subprocess.run(['git', 'diff', '--name-only', '--no-renames', '-z', os.environ['BASE_SHA'], '--'],
                          capture_output=True, text=True, check=True).stdout
    body, branch, number = os.environ.get('PR_BODY', ''), os.environ['PR_BRANCH'], int(os.environ['PR_NUMBER'])
    files = [name for name in diff.split('\0') if name]
    problems = pr_body_problems(body, branch, number, files) + scope_problems(body, branch, number, files)
    try:
        problems += backlog_problems(merged_bodies, body, branch, number)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        problems.append(f'could not read the merged PRs to count the unwired backlog: {error}')
    for problem in problems:
        print(problem)
    if problems:
        print('Declare the product fields as standalone PR body lines; see the product gate in cicd_procedure.md.')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(check_pr())
