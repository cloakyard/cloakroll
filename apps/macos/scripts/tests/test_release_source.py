import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from release_source import capture_source, verify_source


class ReleaseSourceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="CloakRollReleaseSource-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.git("init", "--quiet")
        (self.root / "source.txt").write_text("original\n")
        (self.root / ".gitignore").write_text("build/\n")
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "Fixture")
        self.commit = capture_source(self.root)

    def git(self, *args):
        return subprocess.check_output([
            "git", "-c", "user.name=Release Test", "-c", "user.email=release-test@example.invalid",
            "-c", "commit.gpgSign=false", "-c", "core.hooksPath=/dev/null", *args
        ], cwd=self.root, env=dict(os.environ, GIT_CONFIG_COUNT="0"), text=True).strip()

    def test_ignored_build_outputs_preserve_the_captured_revision(self):
        (self.root / "build").mkdir()
        (self.root / "build/artifact").write_text("generated")
        verify_source(self.root, self.commit)
        self.assertEqual(capture_source(self.root), self.commit)

    def test_unstaged_source_edits_reject_start_and_continuation(self):
        (self.root / "source.txt").write_text("changed")
        with self.assertRaisesRegex(ValueError, "Commit source changes"):
            capture_source(self.root)
        with self.assertRaisesRegex(ValueError, "Source changed"):
            verify_source(self.root, self.commit)

    def test_staged_source_edits_reject_continuation(self):
        (self.root / "source.txt").write_text("changed")
        self.git("add", "source.txt")
        with self.assertRaises(ValueError):
            verify_source(self.root, self.commit)

    def test_untracked_source_rejects_continuation(self):
        (self.root / "new-source.txt").write_text("new")
        with self.assertRaises(ValueError):
            verify_source(self.root, self.commit)

    def test_a_new_clean_commit_cannot_relabel_the_running_build(self):
        self.git("commit", "--allow-empty", "--quiet", "-m", "Another revision")
        self.assertNotEqual(capture_source(self.root), self.commit)
        with self.assertRaises(ValueError):
            verify_source(self.root, self.commit)


if __name__ == "__main__":
    unittest.main()
