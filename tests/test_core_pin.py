"""Pin checks for the shared Brave spec.

Protects: the core gitlink moving off groundwork-core v0.8.0, a token in
.gitmodules, and the Windows host job checking out the repo without that spec.
"""

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CORE_V0_8_0 = "5c8526102170d8f9a9b0a7d102dfdc0a3b66e20d"


class CorePinTest(unittest.TestCase):
    def test_core_gitlink_is_groundwork_core_v0_8_0(self) -> None:
        sha = subprocess.check_output(
            ["git", "rev-parse", "HEAD:core"],
            cwd=REPO,
            text=True,
        ).strip()
        self.assertEqual(sha, CORE_V0_8_0)
        modules = (REPO / ".gitmodules").read_text()
        self.assertIn("path = core", modules)
        self.assertIn("url = https://github.com/jasondockery/groundwork-core.git", modules)
        self.assertNotIn("x-access-token", modules)
        self.assertIn("v0.8.0", (REPO / "README.md").read_text())
        self.assertIn("v0.8.0", (REPO / "AGENTS.md").read_text())

    def test_host_contract_checks_out_submodules(self) -> None:
        workflow = (REPO / ".github/workflows/ci.yml").read_text()
        wrapper, host = workflow.split("host-contract:", 1)
        self.assertNotIn("submodules:", wrapper)
        self.assertIn("submodules: true", host)
        self.assertIn("runs-on: windows-latest", host)
