"""Pin checks for the shared Brave spec.

Protects: the core gitlink drifting from the tag named by `branch =` in
.gitmodules, a token in .gitmodules, and the Windows host job checking out the repo without that spec.
"""

from __future__ import annotations

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
        tag_commit = subprocess.check_output(
            [
                "git",
                "ls-remote",
                "https://github.com/jasondockery/groundwork-core.git",
                f"refs/tags/{tag}^{{}}",
                f"refs/tags/{tag}",
            ],
            cwd=REPO,
            text=True,
        ).splitlines()
        # An annotated tag lists its commit last, on the peeled ^{} line.
        self.assertEqual(sha, tag_commit[-1].split()[0])
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
