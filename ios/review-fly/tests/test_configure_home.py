"""Check startup reconciliation against fresh and existing persistent homes."""
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ConfigureHomeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="review-home-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bundle = self.root / "image bundle"
        self.home = self.root / "persistent home"
        self.files = {
            "bin/herdcats-bridge": b"#!/bin/sh\necho installed-bridge\n",
            "extensions/herdcats/index.ts": b"export default function() {}\n",
            "extensions/herdcats/runtime.mjs": b"export const runtime = true;\n",
            "extensions/herdcats/README.md": b"Extension documentation\n",
            "pi-settings.json": b'{"defaultProvider":"openrouter"}\n',
        }
        for name, content in self.files.items():
            path = self.bundle / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)

    def configure(self):
        return subprocess.run(
            ["sh", str(ROOT / "configure-home.sh"), str(self.bundle), str(self.home)],
            capture_output=True, text=True,
        )

    def test_empty_volume_gets_executable_bridge_and_discoverable_extension(self):
        result = self.configure()
        self.assertEqual(result.returncode, 0, result.stderr)
        bridge = self.home / ".local/bin/herdcats-bridge"
        self.assertEqual(bridge.read_bytes(), self.files["bin/herdcats-bridge"])
        self.assertTrue(os.access(bridge, os.X_OK))
        for name in ("index.ts", "runtime.mjs", "README.md"):
            self.assertEqual(
                (self.home / ".pi/agent/extensions/herdcats" / name).read_bytes(),
                self.files["extensions/herdcats/" + name],
            )
        settings = self.home / ".pi/agent/settings.json"
        self.assertEqual(settings.read_bytes(), self.files["pi-settings.json"])
        self.assertEqual(stat.S_IMODE(settings.stat().st_mode), 0o600)

    def test_restarts_reconcile_managed_files_and_preserve_user_state(self):
        preserved = {
            ".pi/agent/auth.json": b"private fixture credential",
            ".pi/agent/settings.json": b'{"custom":"keep"}',
            ".pi/agent/sessions/project/session.jsonl": b"private fixture history",
            ".pi/agent/extensions/herdr-agent-state.ts": b"existing Herdr extension",
            "projects/sample-app/work.txt": b"review work",
        }
        for name, content in preserved.items():
            path = self.home / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
            path.chmod(0o600)
        for _ in range(2):
            result = self.configure()
            self.assertEqual(result.returncode, 0, result.stderr)
            for name, content in preserved.items():
                self.assertEqual((self.home / name).read_bytes(), content)
                self.assertEqual(stat.S_IMODE((self.home / name).stat().st_mode), 0o600)
            (self.home / ".local/bin/herdcats-bridge").write_text("old managed bridge")
            (self.home / ".pi/agent/extensions/herdcats/runtime.mjs").write_text("old runtime")
        result = self.configure()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / ".local/bin/herdcats-bridge").read_bytes(),
                         self.files["bin/herdcats-bridge"])
        self.assertEqual((self.home / ".pi/agent/extensions/herdcats/runtime.mjs").read_bytes(),
                         self.files["extensions/herdcats/runtime.mjs"])

    def test_symlink_destination_is_rejected_without_writing_its_target(self):
        target = self.root / "unmanaged"
        target.write_text("keep")
        destination = self.home / ".local/bin/herdcats-bridge"
        destination.parent.mkdir(parents=True)
        destination.symlink_to(target)
        result = self.configure()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_text(), "keep")
        self.assertTrue(destination.is_symlink())

    def test_incomplete_image_bundle_does_not_initialize_the_home(self):
        (self.bundle / "extensions/herdcats/runtime.mjs").unlink()
        result = self.configure()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.home.exists())


if __name__ == "__main__":
    unittest.main()
