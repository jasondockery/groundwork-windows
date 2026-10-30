"""Opt-in git-filter-repo: per-user, proven by its help text, hermetic, and never a rewrite."""
import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
HELPER = REPO / 'install-git-filter-repo.sh'
BOOTSTRAP = REPO / 'bootstrap.sh'

# A fake git answers only `git filter-repo -h`, from a state file. A fake pipx
# "installs" by writing that state file. Every call is logged.
FAKE_GIT = """#!/usr/bin/env bash
echo "git $*" >> "$FAKE_LOG"
if [[ "$1" == "filter-repo" && "$2" == "-h" ]]; then
  [[ -f "$FAKE_STATE" ]] && cat "$FAKE_STATE" && exit 0
  echo "git: 'filter-repo' is not a git command." >&2
  exit 1
fi
exit 0
"""
FAKE_PIPX = """#!/usr/bin/env bash
echo "pipx $*" >> "$FAKE_LOG"
case "$1" in
  list) [[ -f "$FAKE_STATE" ]] && echo "git-filter-repo 2.47.0" ; exit 0 ;;
  install|upgrade) printf '%s\\n' "$FAKE_HELP" > "$FAKE_STATE" ;;
esac
exit 0
"""
FAKE_TIMEOUT = '#!/usr/bin/env bash\necho "timeout $*" >> "$FAKE_LOG"\nshift 2\nexec "$@"\n'


class GitFilterRepoTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='groundwork-gfr-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        (self.root / 'home').mkdir()
        # Private PATH: a host pipx or git-filter-repo must never be reached.
        for name in ('bash', 'grep', 'cat', 'env'):
            found = shutil.which(name)
            self.assertTrue(found, name)
            (self.bin / name).symlink_to(found)
        self.log = self.root / 'log'
        self.state = self.root / 'state'
        self.fake('git', FAKE_GIT)

    def fake(self, name, body, directory=None):
        path = (directory or self.bin) / name
        path.write_text(body)
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def run_helper(self, pipx=True, timeout=True, system_dirs='', help_text='usage: git filter-repo --sensitive-data-removal'):
        if pipx:
            self.fake('pipx', FAKE_PIPX)
        if timeout:
            self.fake('timeout', FAKE_TIMEOUT)
        env = {'HOME': str(self.root / 'home'), 'PATH': str(self.bin), 'FAKE_LOG': str(self.log),
               'FAKE_STATE': str(self.state), 'FAKE_HELP': help_text,
               'GROUNDWORK_SYSTEM_BIN_DIRS': system_dirs}
        return subprocess.run(['bash', str(HELPER)], env=env, text=True, capture_output=True, timeout=30)

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_helper_has_a_shebang(self):
        self.assertEqual(HELPER.read_text().splitlines()[0], '#!/usr/bin/env bash')

    def test_installs_per_user_with_pipx_under_a_timeout_and_checks_the_help_text(self):
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls().count('pipx install git-filter-repo'), 1)
        self.assertIn('timeout --kill-after=5s 300 pipx install git-filter-repo', self.calls())
        self.assertIn('git filter-repo -h', self.calls())
        self.assertIn('installed for this user', result.stdout)

    def test_second_run_is_idempotent(self):
        self.run_helper()
        self.log.unlink()
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse([c for c in self.calls() if c.startswith('pipx')])

    def test_old_build_without_the_flag_fails_the_proof_without_failing_setup(self):
        result = self.run_helper(help_text='usage: git filter-repo (older build)')
        self.assertEqual(result.returncode, 0)
        self.assertIn('does not list --sensitive-data-removal', result.stderr)
        self.assertNotIn('installed for this user', result.stdout)

    def test_missing_pipx_or_timeout_installs_nothing(self):
        for kwargs, message in (({'pipx': False}, 'pipx is not installed'), ({'timeout': False}, 'GNU timeout is required')):
            with self.subTest(kwargs=kwargs):
                for name in ('pipx', 'timeout'):
                    (self.bin / name).unlink(missing_ok=True)
                self.state.unlink(missing_ok=True)
                self.log.unlink(missing_ok=True)
                result = self.run_helper(**kwargs)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(message, result.stderr)
                self.assertFalse(self.state.exists())
                self.assertFalse([c for c in self.calls() if c.startswith('pipx')])

    def test_system_dirs_are_unreachable_unless_the_override_names_them(self):
        system = self.root / 'system-bin'
        system.mkdir()
        self.fake('pipx', FAKE_PIPX, system)
        # Sealed: the override is empty, so the system-dir pipx never runs.
        result = self.run_helper(pipx=False, system_dirs='')
        self.assertIn('pipx is not installed', result.stderr)
        self.assertFalse(self.state.exists())
        self.assertFalse([c for c in self.calls() if c.startswith('pipx')])
        # Control: naming that dir makes the same script reach it, so the seal is the override.
        self.log.unlink(missing_ok=True)
        self.run_helper(pipx=False, system_dirs=str(system))
        self.assertIn('pipx install git-filter-repo', self.calls())
        self.assertTrue(self.state.exists())

    def test_helper_has_no_root_or_rewrite_commands_and_runs_none(self):
        text = HELPER.read_text()
        for forbidden in ('sudo', 'apt', 'filter-branch', 'git push', '--force', '--replace-text', '--invert-paths'):
            self.assertNotIn(forbidden, text)
        self.run_helper()
        for call in self.calls():
            self.assertTrue(call == 'git filter-repo -h' or call.startswith(('pipx', 'timeout')), call)

    def test_bootstrap_only_installs_on_the_explicit_flag(self):
        text = BOOTSTRAP.read_text()
        self.assertIn('--with-git-filter-repo', text)
        self.assertIn('install-git-filter-repo.sh', text)

    def test_bootstrap_flag_runs_the_helper_only_when_asked(self):
        scripts = self.root / 'scripts'
        scripts.mkdir()
        # Point the Omarchy check at a missing dir so this runs on an Omarchy host too.
        (scripts / 'bootstrap.sh').write_text(BOOTSTRAP.read_text().replace('/usr/share/omarchy', str(self.root / 'no-omarchy')))
        marker = self.root / 'helper-ran'
        (scripts / 'install-git-filter-repo.sh').write_text(f'#!/usr/bin/env bash\ntouch {marker}\n')
        for name in ('dirname', 'mkdir', 'touch', 'tail'):
            (self.bin / name).symlink_to(shutil.which(name))
        self.fake('uname', '#!/usr/bin/env bash\n[[ "$1" == -s ]] && echo Linux || echo 6.1.0-microsoft-standard-WSL2\n')
        self.fake('chezmoi', '#!/usr/bin/env bash\nexit 0\n')
        self.fake('git', '#!/usr/bin/env bash\n[[ "$1" == clone ]] && mkdir -p "${@: -1}"\nexit 0\n')
        for args, expected in ((['--help'], False), (['--bogus'], False), ([], False), (['--with-git-filter-repo'], True)):
            with self.subTest(args=args):
                marker.unlink(missing_ok=True)
                env = {'PATH': str(self.bin), 'HOME': str(self.root / 'home'),
                       'GROUNDWORK_ENGINE_DIR': str(self.root / f'engine-{len(args)}-{expected}')}
                subprocess.run(['bash', str(scripts / 'bootstrap.sh'), *args], env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(marker.exists(), expected)


if __name__ == '__main__':
    unittest.main()
