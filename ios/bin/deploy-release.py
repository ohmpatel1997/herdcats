#!/usr/bin/env python3
"""Maintainer release PR preparation and verified App Store Connect upload."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(*args, cwd=None, capture=False):
    result = subprocess.run(args, cwd=cwd or ROOT, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def git(*args, **kwargs):
    return run('git', *args, **kwargs)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def confirm(message):
    require(input(message + ' [y/N]: ').strip().lower() == 'y', 'Cancelled.')


def version_at(ref):
    content = git('show', f'{ref}:ios/project.yml', capture=True)
    return re.search(r'CFBundleShortVersionString:\s*"([0-9.]+)"', content)[1]


def clean():
    require(not git('status', '--porcelain', capture=True),
            'Working tree is dirty. Commit or stash changes first.')


def validate_pr(pr):
    require(pr['state'] == 'MERGED', 'PR must be merged before publishing.')
    require(pr['baseRefName'] == 'main', 'Release PR must target main.')
    require(pr['headRefName'].startswith('release/'), 'Expected a release/* PR.')
    sha = pr['mergeCommit']['oid']
    require(re.fullmatch(r'[0-9a-f]{40}', sha), 'Invalid merge commit.')
    return sha


def validate_ci(runs, sha):
    # Require the newest main push run, never a PR run or a success from an older attempt.
    pushes = [r for r in runs if r['headSha'] == sha and r['event'] == 'push']
    require(pushes and pushes[0]['status'] == 'completed'
            and pushes[0]['conclusion'] == 'success',
            'The latest CI push run for the merged commit must complete successfully. Retry publish after CI passes.')


def prepare(version):
    clean()
    git('fetch', 'origin', 'main', '--tags')
    if not version:
        run(str(ROOT / 'ios/bin/next-version'), 'origin/main')
        version = input('Release version (MAJOR.MINOR.PATCH): ').strip()
    require(re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version), 'Invalid release version.')
    branch = f'release/{version}'
    current = git('branch', '--show-current', capture=True)
    notes = ROOT / f'ios/releases/{version}.txt'
    # A prepared branch can be retried after a network failure without another bump.
    if current == branch and notes.exists():
        require(version_at('HEAD') == version, 'Branch version does not match requested version.')
        require(git('merge-base', 'origin/main', 'HEAD', capture=True) != git('rev-parse', 'HEAD', capture=True),
                'This release is already on main. Use publish with its PR number.')
    else:
        app_tags = git('tag', '--list', 'herdrcat-v*', capture=True).splitlines()
        require(f'herdrcat-v{version}' not in app_tags, 'Version already tagged.')
        old_version = version_at('origin/main')
        requested = tuple(map(int, version.split('.')))
        previous = tuple(map(int, old_version.split('.')))
        # next-version retains project.yml's version for an untagged first release.
        # The release helper still increments the build number in this case.
        require(requested > previous or (requested == previous and not app_tags),
                f'Choose a version higher than {old_version} '
                '(the current version is allowed only before the first app tag).')
        confirm(f'Create {branch} from origin/main and prepare {version}?')
        git('switch', '-c', branch, 'origin/main')
        # Use the previous app version's tag when available; otherwise the nearest
        # ancestor app tag. Only include commits reachable from the release source.
        tags = git('tag', '--merged', 'HEAD', '--sort=-version:refname',
                   '--list', 'herdrcat-v*', capture=True).splitlines()
        if tags:
            run(str(ROOT / 'ios/bin/changelog'), tags[0].removeprefix('herdrcat-v'))
            text = (ROOT / 'ios/fastlane/changelog.txt').read_text()
        else:
            text = git('log', '--format=%s', 'HEAD', '--', 'ios/', capture=True) + '\n'
        notes.parent.mkdir(exist_ok=True)
        notes.write_text(text)
        print(f'\nReview TestFlight notes: {notes}\n{text}', flush=True)
        editor = os.environ.get('EDITOR')
        if editor:
            # Treat EDITOR as an executable, consistent with bin/beta.
            run(editor, str(notes))
        confirm('Are these notes ready for PR review? Edit the file in another terminal if needed')
        require(notes.read_text().strip(), 'Release notes cannot be empty.')
        git('add', str(notes.relative_to(ROOT)))
        git('commit', '-m', f'docs(release): TestFlight notes for {version}')
        run(str(ROOT / 'ios/bin/release'), version)
    print(git('show', 'HEAD:ios/project.yml', capture=True), flush=True)
    confirm('Is this build number higher than every build already uploaded to App Store Connect?')
    git('push', '-u', 'origin', branch)
    existing = json.loads(run('gh', 'pr', 'list', '--head', branch, '--base', 'main',
                              '--state', 'open', '--json', 'url', capture=True))
    if existing:
        print(existing[0]['url'])
    else:
        with tempfile.NamedTemporaryFile(mode='w', suffix='.md') as body:
            body.write(f'Prepare iOS {version} for App Store Connect.\n\n'
                       f'Review version/build and `ios/releases/{version}.txt`. '
                       'After merge and successful main CI, run '
                       '`./ios/bin/deploy publish <PR-number>`.\n\n'
                       'No tag, upload, or App Store submission is created by this PR.\n')
            body.flush()
            run('gh', 'pr', 'create', '--base', 'main', '--head', branch,
                '--title', f'chore(release): iOS {version}', '--body-file', body.name)
    print('After review, merge and passing main CI: ./ios/bin/deploy publish <PR-number>')


def publish(number):
    clean()
    require(re.fullmatch(r'[A-Z0-9]{10}', os.environ.get('DEVELOPMENT_TEAM', '')),
            'Set DEVELOPMENT_TEAM to your 10-character Apple Team ID.')
    pr = json.loads(run('gh', 'pr', 'view', number, '--json',
                        'state,baseRefName,headRefName,mergeCommit', capture=True))
    sha = validate_pr(pr)
    git('fetch', 'origin', 'main', '--tags')
    git('merge-base', '--is-ancestor', sha, 'origin/main')
    runs = json.loads(run('gh', 'run', 'list', '--commit', sha, '--workflow', 'ci.yml',
                          '--event', 'push', '--limit', '20', '--json',
                          'headSha,status,conclusion,event', capture=True))
    validate_ci(runs, sha)
    version = version_at(sha)
    require(pr['headRefName'] == f'release/{version}', 'PR branch and merged version disagree.')
    notes = git('show', f'{sha}:ios/releases/{version}.txt', capture=True)
    require(notes, 'Merged release notes are empty.')
    print(f'\nUpload iOS {version} from tested commit {sha}\n\n{notes}\n', flush=True)
    confirm('Continue to signing and App Store Connect upload?')
    # A detached worktree preserves the caller branch and builds the exact CI SHA.
    parent = Path(tempfile.mkdtemp(prefix='herdcats-publish-'))
    checkout = parent / 'source'
    try:
        git('worktree', 'add', '--detach', str(checkout), sha)
        (checkout / 'ios/fastlane/changelog.txt').write_text(notes + '\n')
        run(str(checkout / 'ios/bin/beta'), cwd=checkout)
    finally:
        if checkout.exists():
            git('worktree', 'remove', '--force', str(checkout))
        shutil.rmtree(parent, ignore_errors=True)
    print('Uploaded to App Store Connect. Check processing and tester availability in TestFlight.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='stage', required=True)
    prep = sub.add_parser('prepare', help='Create a version/changelog release PR')
    prep.add_argument('version', nargs='?')
    pub = sub.add_parser('publish', help='Upload an exact merged, CI-tested release PR')
    pub.add_argument('pr_number', type=int)
    args = parser.parse_args()
    for tool in ('git', 'gh'):
        require(shutil.which(tool), f'{tool} is required.')
    if args.stage == 'prepare':
        prepare(args.version)
    else:
        publish(str(args.pr_number))


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, EOFError, KeyboardInterrupt) as error:
        raise SystemExit(f'Deploy stopped: {error}') from None
