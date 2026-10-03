"""Portable doctor regression tests using disposable repositories and tool stubs."""

import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
REQUIRED_FILES = (
    "Project.yml", "Makefile", "README.md", "AGENTS.md",
    "docs/ROADMAP.md", "docs/HARNESS.md", "docs/MISSION.md",
    "docs/ONBOARDING.md", "scripts/embed-boris.sh", "scripts/doctor.sh",
)


class DoctorTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="solipsist-doctor-tests-")
        self.addCleanup(temporary.cleanup)
        self.temp = Path(temporary.name).resolve()
        self.root = self.temp / "workspace" / "nested" / "project"
        self.root.mkdir(parents=True)
        for relative in REQUIRED_FILES:
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO_ROOT / relative, target)
        git = shutil.which("git")
        self.assertIsNotNone(git)
        subprocess.run([git, "init", "--quiet", str(self.root)], check=True)
        subprocess.run(
            [git, "-C", str(self.root), "add", "--", *REQUIRED_FILES],
            check=True,
        )

        self.bin = self.temp / "bin"
        self.bin.mkdir()
        # Restrict lookup to known tools so the host's Boris/Xcode installations
        # cannot change the outcomes. Missing optional tools remain warnings.
        for name in ("git", "tr", "grep", "head"):
            executable = shutil.which(name)
            self.assertIsNotNone(executable)
            (self.bin / name).symlink_to(executable)
        self.environment = {
            "PATH": str(self.bin),
            "HOME": str(self.temp),
            "LC_ALL": "C",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
        }
        self.write_tool("uname", "printf 'Darwin\\n'\n")
        self.write_tool("sw_vers", "printf '27.2\\n'\n")
        self.write_tool("xcodebuild", "printf 'Xcode 27.0\\nBuild version 27A266a\\n'\n")

    def write_tool(self, name, body):
        target = self.bin / name
        target.write_text("#!/bin/sh\n" + body, encoding="utf-8")
        target.chmod(0o755)
        return target

    def make_engine(self, relative):
        target = self.temp / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        target.chmod(0o755)
        return target

    def run_doctor(self):
        return subprocess.run(
            ["/bin/bash", str(self.root / "scripts/doctor.sh")],
            cwd=self.root,
            env=self.environment,
            capture_output=True,
            text=True,
            timeout=10,
        )

    def test_working_xcode_reports_version(self):
        result = self.run_doctor()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("doctor: ok — xcodebuild: Xcode 27.0", result.stdout)
        self.assertIn("doctor: healthy", result.stdout)

    def test_failing_xcode_is_a_hard_failure(self):
        self.write_tool(
            "xcodebuild",
            "printf 'Xcode 27.0\\n'\n"
            "echo 'xcode-select: tool xcodebuild requires Xcode' >&2\n"
            "exit 7\n",
        )
        result = self.run_doctor()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("xcodebuild -version failed (exit 7)", result.stderr)
        self.assertIn("xcode-select: tool xcodebuild requires Xcode", result.stderr)
        self.assertIn("doctor: FAILED", result.stderr)
        self.assertNotIn("doctor: healthy", result.stdout)
        self.assertNotIn("doctor: ok — xcodebuild:", result.stdout)

    def test_path_only_engine_does_not_report_resolution(self):
        self.write_tool("boris", "printf 'boris/0.8.1\\n'\n")
        result = self.run_doctor()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("no boris binary found", result.stderr)
        self.assertIn("set SOLIPSIST_BORIS_BIN", result.stderr)
        self.assertNotIn("boris engine resolves to:", result.stdout)

    def test_explicit_engine_override_is_accepted(self):
        engine = self.make_engine("engine kit/boris")
        self.environment["SOLIPSIST_BORIS_BIN"] = str(engine)
        result = self.run_doctor()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"boris engine resolves to: {engine}", result.stdout)
        self.assertNotIn("no boris binary found", result.stderr)

    def test_invalid_override_falls_back_to_supported_kit(self):
        self.environment["SOLIPSIST_BORIS_BIN"] = str(self.temp / "missing-engine")
        kit = self.root / "SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris"
        engine = self.make_engine(kit.relative_to(self.temp))
        result = self.run_doctor()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"boris engine resolves to: {engine}", result.stdout)

    def test_missing_xcode_is_a_hard_failure(self):
        (self.bin / "xcodebuild").unlink()
        result = self.run_doctor()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("xcodebuild not found", result.stderr)
        self.assertIn("doctor: FAILED", result.stderr)

    def test_non_mac_skips_xcode_check(self):
        self.write_tool("uname", "printf 'Linux\\n'\n")
        marker = self.temp / "xcode-was-called"
        self.write_tool("xcodebuild", f"printf called > {shlex.quote(str(marker))}\nexit 1\n")
        result = self.run_doctor()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("not macOS", result.stderr)
        self.assertNotIn("xcodebuild:", result.stdout)
        self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
