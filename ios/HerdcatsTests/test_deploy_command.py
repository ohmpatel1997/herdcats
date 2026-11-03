"""Deployment guards run without GitHub, Apple credentials, or uploads."""
import importlib.util
from pathlib import Path
import tempfile
import subprocess
import shutil
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'bin/deploy-release.py'
spec = importlib.util.spec_from_file_location('deploy_release', SCRIPT)
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)
SHA = 'a' * 40


class DeployTests(unittest.TestCase):
    def pr(self, **changes):
        return dict(state='MERGED', baseRefName='main', headRefName='release/1.0.0',
                    mergeCommit={'oid': SHA}, **changes)

    def test_unmerged_wrong_base_and_nonrelease_pr_rejected(self):
        for key, value in [('state', 'OPEN'), ('baseRefName', 'other'),
                           ('headRefName', 'feature')]:
            pr = self.pr()
            pr[key] = value
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                deploy.validate_pr(pr)
        self.assertEqual(deploy.validate_pr(self.pr()), SHA)

    def test_ci_requires_exact_sha_successful_main_push(self):
        good = dict(headSha=SHA, event='push', status='completed', conclusion='success')
        deploy.validate_ci([good], SHA)
        for key, value in [('headSha', 'b' * 40), ('event', 'pull_request'),
                           ('status', 'in_progress'), ('conclusion', 'failure'),
                           ('conclusion', 'cancelled')]:
            bad = dict(good, **{key: value})
            with self.subTest(key=key, value=value), self.assertRaises(RuntimeError):
                deploy.validate_ci([bad], SHA)
        with self.assertRaises(RuntimeError):
            deploy.validate_ci([], SHA)
        with self.assertRaises(RuntimeError):
            deploy.validate_ci([dict(good, conclusion='failure'), good], SHA)

    def test_prepare_creates_reviewed_notes_before_bump_and_pr(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'ios/fastlane').mkdir(parents=True)
            calls = []
            def fake_git(*args, **kwargs):
                calls.append(args)
                if args[:2] == ('branch', '--show-current'):
                    return 'main'
                if args[:2] == ('tag', '--merged'):
                    return 'herdrcat-v0.8.0'
                return ''
            def fake_run(*args, **kwargs):
                calls.append(args)
                if args[0] == str(root / 'ios/bin/changelog'):
                    self.assertEqual(args[1], '0.8.0')
                    (root / 'ios/fastlane/changelog.txt').write_text('New feature\n')
                if args[0] == str(root / 'ios/bin/release'):
                    self.assertTrue(any(c[:2] == ('commit', '-m') for c in calls))
                if args[:3] == ('gh', 'pr', 'list'):
                    return '[]'
            with patch.object(deploy, 'ROOT', root), patch.object(deploy, 'clean'), \
                 patch.object(deploy, 'version_at', return_value='0.8.0'), \
                 patch.object(deploy, 'confirm'), patch.dict(deploy.os.environ, EDITOR=''), \
                 patch.object(deploy, 'git', side_effect=fake_git), \
                 patch.object(deploy, 'run', side_effect=fake_run):
                deploy.prepare('0.9.0')
            self.assertEqual((root / 'ios/releases/0.9.0.txt').read_text(), 'New feature\n')
            self.assertIn(('switch', '-c', 'release/0.9.0', 'origin/main'), calls)
            self.assertTrue(any(c[:3] == ('gh', 'pr', 'create') for c in calls))

    def test_interactive_first_release_accepts_current_version_without_tags(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'ios').mkdir()
            def fake_git(*args, **kwargs):
                if args[:2] == ('branch', '--show-current'):
                    return 'main'
                if args[:1] == ('log',):
                    return 'Initial iOS app'
                return ''
            with patch.object(deploy, 'ROOT', root), patch.object(deploy, 'clean'), \
                 patch.object(deploy, 'version_at', return_value='0.8.0'), \
                 patch.object(deploy, 'confirm'), patch('builtins.input', return_value='0.8.0'), \
                 patch.dict(deploy.os.environ, EDITOR=''), \
                 patch.object(deploy, 'git', side_effect=fake_git) as git, \
                 patch.object(deploy, 'run', return_value='[]') as run:
                deploy.prepare(None)
                git.assert_any_call('switch', '-c', 'release/0.8.0', 'origin/main')
                run.assert_any_call(str(root / 'ios/bin/release'), '0.8.0')
                self.assertTrue(any(c.args[:3] == ('gh', 'pr', 'create')
                                    for c in run.call_args_list))
                self.assertEqual((root / 'ios/releases/0.8.0.txt').read_text(), 'Initial iOS app\n')

    def test_version_validation_still_rejects_downgrades_and_tagged_reuse(self):
        for version, tags in [('0.7.0', ''), ('0.8.0', 'herdrcat-v0.7.0'),
                              ('0.8.0', 'herdrcat-v0.8.0')]:
            def fake_git(*args, **kwargs):
                if args[:2] == ('branch', '--show-current'):
                    return 'main'
                if args[:2] == ('tag', '--list'):
                    # Both the old exact-tag check and new all-app-tags lookup.
                    return tags if args[2] in ('herdrcat-v*', tags) else ''
                return ''
            with self.subTest(version=version, tags=tags), \
                 patch.object(deploy, 'clean'), \
                 patch.object(deploy, 'version_at', return_value='0.8.0'), \
                 patch.object(deploy, 'git', side_effect=fake_git) as git, \
                 patch.object(deploy, 'run') as run:
                with self.assertRaises(RuntimeError):
                    deploy.prepare(version)
                self.assertFalse(any(c.args[:1] == ('switch',) for c in git.call_args_list))
                run.assert_not_called()

    def test_prepared_branch_retry_does_not_bump_or_duplicate_pr(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            notes = root / 'ios/releases/1.0.0.txt'
            notes.parent.mkdir(parents=True)
            notes.write_text('Reviewed notes')
            def fake_git(*args, **kwargs):
                if args[:2] == ('branch', '--show-current'):
                    return 'release/1.0.0'
                if args[:1] == ('merge-base',):
                    return 'base'
                return SHA
            with patch.object(deploy, 'ROOT', root), patch.object(deploy, 'clean'), \
                 patch.object(deploy, 'version_at', return_value='1.0.0'), \
                 patch.object(deploy, 'confirm'), patch.object(deploy, 'git', side_effect=fake_git), \
                 patch.object(deploy, 'run', return_value='[{"url":"https://example.invalid/pr/1"}]') as run:
                deploy.prepare('1.0.0')
                self.assertEqual(run.call_count, 1)
                self.assertEqual(run.call_args.args[:3], ('gh', 'pr', 'list'))

    def test_interactive_prepare_suggests_from_fetched_main_before_prompt(self):
        with patch.object(deploy, 'clean'), patch.object(deploy, 'git') as git, \
             patch.object(deploy, 'run') as run, \
             patch('builtins.input', side_effect=EOFError) as prompt:
            with self.assertRaises(EOFError):
                deploy.prepare(None)
            git.assert_called_once_with('fetch', 'origin', 'main', '--tags')
            run.assert_called_once_with(str(deploy.ROOT / 'ios/bin/next-version'), 'origin/main')
            prompt.assert_called_once()

    def test_next_version_uses_fetched_main_with_outdated_checkout(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            def git(*args):
                return subprocess.check_output(['git', '-C', temp, *args], text=True,
                                               stderr=subprocess.DEVNULL).strip()
            git('init', '-b', 'main')
            git('config', 'user.name', 'Release Test')
            git('config', 'user.email', 'release-test@example.invalid')
            git('config', 'core.hooksPath', str(root / 'no-hooks'))
            (root / 'ios/bin').mkdir(parents=True)
            shutil.copy2(SCRIPT.parent / 'next-version', root / 'ios/bin/next-version')
            project = root / 'ios/project.yml'
            project.write_text('CFBundleShortVersionString: "0.8.0"\n')
            git('add', '.')
            git('commit', '-m', 'initial release')
            git('tag', 'herdrcat-v0.8.0')
            old_head = git('rev-parse', 'HEAD')
            project.write_text('CFBundleShortVersionString: "0.8.0"\n# new feature\n')
            git('add', '.')
            git('commit', '-m', 'feat(ios): add a feature')
            git('update-ref', 'refs/remotes/origin/main', 'HEAD')
            git('checkout', '--detach', old_head)
            def suggest(*args):
                return subprocess.run(['bash', str(root / 'ios/bin/next-version'), *args],
                                      text=True, capture_output=True)
            self.assertNotEqual(suggest().returncode, 0)  # stale HEAD has no changes
            result = suggest('origin/main')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Suggested next version: 0.9.0', result.stdout)
            self.assertEqual(git('rev-parse', 'HEAD'), old_head)
            self.assertEqual(git('status', '--porcelain'), '')
            # Without tags, read the source ref's project version, not the stale file.
            git('tag', '-d', 'herdrcat-v0.8.0')
            git('checkout', 'main')
            project.write_text('CFBundleShortVersionString: "0.9.0"\n')
            git('add', '.')
            git('commit', '-m', 'version fixture')
            git('update-ref', 'refs/remotes/origin/main', 'HEAD')
            git('checkout', '--detach', old_head)
            result = suggest('origin/main')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Suggested next version: 0.9.0', result.stdout)
            self.assertEqual(git('rev-parse', 'HEAD'), old_head)

    def test_failed_ci_never_creates_checkout_or_uploads(self):
        import json
        with patch.dict(deploy.os.environ, DEVELOPMENT_TEAM='ABCDEFGHIJ'), \
             patch.object(deploy, 'clean'), patch.object(deploy, 'git') as git, \
             patch.object(deploy, 'run', side_effect=[json.dumps(self.pr()), '[]']) as run:
            with self.assertRaises(RuntimeError):
                deploy.publish('42')
            self.assertFalse(any(call.args[:2] == ('worktree', 'add') for call in git.call_args_list))
            self.assertEqual(run.call_count, 2)

    def test_publish_uses_merged_notes_exact_sha_and_cleans_failed_upload(self):
        import json
        good = dict(headSha=SHA, event='push', status='completed', conclusion='success')
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            checkout = root / 'source'
            def fake_git(*args, **kwargs):
                if args[:2] == ('worktree', 'add'):
                    (checkout / 'ios/fastlane').mkdir(parents=True)
                if args[:1] == ('show',):
                    return 'Reviewed release notes'
            def fake_run(*args, **kwargs):
                if args[:3] == ('gh', 'pr', 'view'):
                    return json.dumps(self.pr())
                if args[:3] == ('gh', 'run', 'list'):
                    return json.dumps([good])
                self.assertEqual(args, (str(checkout / 'ios/bin/beta'),))
                self.assertEqual((checkout / 'ios/fastlane/changelog.txt').read_text(),
                                 'Reviewed release notes\n')
                raise RuntimeError('upload failed')
            with patch.dict(deploy.os.environ, DEVELOPMENT_TEAM='ABCDEFGHIJ'), \
                 patch.object(deploy, 'clean'), patch.object(deploy, 'confirm'), \
                 patch.object(deploy, 'version_at', return_value='1.0.0'), \
                 patch.object(deploy.tempfile, 'mkdtemp', return_value=temp), \
                 patch.object(deploy, 'git', side_effect=fake_git) as git, \
                 patch.object(deploy, 'run', side_effect=fake_run):
                with self.assertRaisesRegex(RuntimeError, 'upload failed'):
                    deploy.publish('42')
                git.assert_any_call('worktree', 'add', '--detach', str(checkout), SHA)
                git.assert_any_call('worktree', 'remove', '--force', str(checkout))


if __name__ == '__main__':
    unittest.main(verbosity=2)
