"""Wrapper fixtures; successful paths run on a non-Omarchy Linux proof host."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
STUB = '''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ['WRAPPER_FIXTURE'])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / 'calls').open('a') as log:
    log.write(json.dumps([name, *args]) + '\\n')
if name == 'uname':
    print(os.environ.get('FIXTURE_OS', 'Linux') if args == ['-s'] else os.environ.get('FIXTURE_KERNEL', '6.1.0-microsoft-standard-WSL2'))
elif name == 'chezmoi':
    (root / 'applied').write_text('applied')
elif name == 'git':
    if args[0] == 'clone':
        dest = pathlib.Path(args[-1]); dest.mkdir(parents=True)
        (dest / 'bootstrap-mac.sh').write_text('printf applied > "$WRAPPER_FIXTURE/applied"\\n')
    elif args[-2:] == ['rev-parse', '--show-toplevel']:
        print(args[1])
    elif args[-3:] == ['remote', 'get-url', 'origin']:
        print(os.environ.get('FIXTURE_ORIGIN', 'https://github.com/jasondockery/groundwork-mac.git'))
    elif args[-2:] == ['status', '--porcelain']:
        if os.environ.get('FIXTURE_STATUS_FAILURE'):
            raise SystemExit(128)
        print(os.environ.get('FIXTURE_DIRTY', ''), end='')
    else:
        raise SystemExit('Unexpected Git command')
'''


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='groundwork-wrapper-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'; self.bin.mkdir()
        stub = self.bin / 'stub'; stub.write_text(STUB); stub.chmod(0o755)
        for name in ('uname', 'git', 'chezmoi'):
            (self.bin / name).symlink_to(stub)
        self.env = dict(os.environ, WRAPPER_FIXTURE=str(self.root),
                        PATH=f'{self.bin}:/usr/bin:/bin', HOME=str(self.root),
                        GROUNDWORK_ENGINE_DIR=str(self.root / 'engine'))
        self.env.pop('GROUNDWORK_REPO_URL', None)

    def run_wrapper(self, *args, status=0):
        result = subprocess.run(['bash', str(REPO / 'bootstrap.sh'), *args], env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, status, result.stdout + result.stderr)
        return result

    def calls(self):
        log = self.root / 'calls'
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def test_help_and_invalid_input_have_no_external_effects(self):
        self.run_wrapper('--help')
        self.run_wrapper('--typo', status=64)
        self.run_wrapper('unexpected', status=64)
        self.assertEqual(self.calls(), [])

    def test_other_os_is_refused_before_git(self):
        self.env['FIXTURE_OS'] = 'Darwin'
        self.run_wrapper(status=1)
        self.assertTrue(all(call[0] == 'uname' for call in self.calls()))

    def test_omarchy_is_refused_before_git(self):
        (self.bin / 'omarchy').symlink_to(self.bin / 'stub')
        self.run_wrapper(status=1)
        self.assertTrue(all(call[0] == 'uname' for call in self.calls()))

    def test_non_wsl2_kernel_is_refused_before_git(self):
        for kernel in ('6.1.0-generic', '4.4.0-Microsoft'):
            with self.subTest(kernel=kernel):
                self.env['FIXTURE_KERNEL'] = kernel
                self.run_wrapper(status=1)
                self.assertTrue(all(call[0] == 'uname' for call in self.calls()))

    @unittest.skipIf(Path('/usr/share/omarchy').exists(), 'positive wrapper boundary requires a non-Omarchy host; covered in CI')
    def test_prepare_then_apply_and_reject_dirty_engine(self):
        self.run_wrapper('--prepare-only')
        self.assertFalse((self.root / 'applied').exists())
        self.run_wrapper()
        self.assertEqual((self.root / 'applied').read_text(), 'applied')
        (self.root / 'applied').unlink()
        self.env['FIXTURE_DIRTY'] = ' M user-file'
        self.run_wrapper(status=1)
        self.assertFalse((self.root / 'applied').exists())

    @unittest.skipIf(Path('/usr/share/omarchy').exists(), 'positive wrapper boundary requires a non-Omarchy host; covered in CI')
    def test_unreadable_engine_status_stops_before_apply(self):
        self.run_wrapper('--prepare-only')
        self.env['FIXTURE_STATUS_FAILURE'] = '1'
        result = self.run_wrapper(status=1)
        self.assertIn('Cannot inspect', result.stderr)
        self.assertFalse((self.root / 'applied').exists())
        self.assertTrue((self.root / 'engine').exists())

    @unittest.skipIf(Path('/usr/share/omarchy').exists(), 'positive wrapper boundary requires a non-Omarchy host; covered in CI')
    def test_existing_ssh_origin_requires_explicit_selection_and_is_preserved(self):
        (self.root / 'engine').mkdir()
        ssh_origin = 'git@github-my-account:jasondockery/groundwork-mac.git'
        self.env['FIXTURE_ORIGIN'] = ssh_origin
        result = self.run_wrapper('--prepare-only', status=1)
        self.assertIn('origin differs', result.stderr)
        self.env['GROUNDWORK_REPO_URL'] = ssh_origin
        self.run_wrapper('--prepare-only')
        self.assertFalse((self.root / 'applied').exists())
        self.assertFalse(any(call[1:2] == ['clone'] for call in self.calls()))
        self.assertFalse(any('set-url' in call for call in self.calls()))

    @unittest.skipIf(Path('/usr/share/omarchy').exists(), 'positive wrapper boundary requires a non-Omarchy host; covered in CI')
    def test_wrong_engine_origin_is_preserved(self):
        self.run_wrapper('--prepare-only')
        self.env['FIXTURE_ORIGIN'] = 'git@github.com:someone/unrelated.git'
        self.run_wrapper(status=1)
        self.assertFalse((self.root / 'applied').exists())


if __name__ == '__main__':
    unittest.main()
