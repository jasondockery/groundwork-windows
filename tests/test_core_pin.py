"""Pin checks for the shared Brave spec.

Protects: the core gitlink drifting from the tag named by `branch =` in
.gitmodules, a token in .gitmodules, and the Windows host job checking out the repo without that spec.
"""

from __future__ import annotations

import os
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


class CorePinTest(unittest.TestCase):
    def test_core_gitlink_matches_gitmodules_branch_tag(self) -> None:
        sha = subprocess.check_output(
            ["git", "rev-parse", "HEAD:core"],
            cwd=REPO,
            text=True,
        ).strip()
        tag = subprocess.check_output(
            ["git", "config", "--file", ".gitmodules", "submodule.core.branch"],
            cwd=REPO,
            text=True,
        ).strip()
        self.assertRegex(tag, r"^v\d+\.\d+\.\d+$")
        tagged = None
        if (REPO / "core" / ".git").exists():
            local = subprocess.run(
                ["git", "-C", "core", "rev-parse", "-q", "--verify", f"refs/tags/{tag}^{{commit}}"],
                cwd=REPO,
                capture_output=True,
                text=True,
            )
            if local.returncode == 0:
                tagged = local.stdout.strip()
        if tagged is None:
            # CI may check core out without tags, so ask the remote. An empty global
            # config keeps an insteadOf https->ssh rule from breaking the lookup.
            env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_TERMINAL_PROMPT="0")
            listing = subprocess.run(
                [
                    "git",
                    "ls-remote",
                    "https://github.com/jasondockery/groundwork-core.git",
                    f"refs/tags/{tag}",
                    f"refs/tags/{tag}^{{}}",
                ],
                cwd=REPO,
                capture_output=True,
                text=True,
                env=env,
            )
            if listing.returncode != 0 or not listing.stdout.strip():
                if os.environ.get("CI"):
                    self.fail(f"cannot resolve tag {tag}: {listing.stderr.strip()}")
                self.skipTest(f"tag {tag} is not in a local core checkout and the remote is unreachable")
            # An annotated tag lists its commit last, on the peeled ^{} line.
            tagged = listing.stdout.splitlines()[-1].split()[0]
        self.assertEqual(sha, tagged)
        modules = (REPO / ".gitmodules").read_text()
        self.assertIn("path = core", modules)
        self.assertIn("url = https://github.com/jasondockery/groundwork-core.git", modules)
        self.assertNotIn("x-access-token", modules)

    def test_host_contract_checks_out_submodules(self) -> None:
        workflow = (REPO / ".github/workflows/ci.yml").read_text()
        wrapper, host = workflow.split("host-contract:", 1)
        self.assertNotIn("submodules:", wrapper)
        self.assertIn("submodules: true", host)
        self.assertIn("runs-on: windows-latest", host)
