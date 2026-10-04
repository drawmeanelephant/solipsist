"""Run the compiled spike against disposable corpora and a contract stub."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]
SPIKE = Path(os.environ.get("SOLIPSIST_SPIKE_BIN", REPO / "build/Build/Products/Debug/boris-spike"))
FIXTURES = REPO / "Tests/Fixtures"


class SpikeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not SPIKE.is_file():
            raise RuntimeError("Build the spike before running CLI regressions.")

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="solipsist-spike-tests-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.content = self.root / "publication/content"
        self.content.mkdir(parents=True)
        (self.content.parent / "boris.json").write_text("{}", encoding="utf-8")
        (self.content / "page.md").write_text("untouched authored content", encoding="utf-8")
        self.calls = self.root / "calls.jsonl"
        self.config = self.root / "config.json"
        self.binary = self.root / "boris"
        self.binary.write_text(
            f"#!{sys.executable}\n" + ENGINE_STUB, encoding="utf-8"
        )
        self.binary.chmod(0o700)
        self.environment = dict(os.environ)
        self.environment.update(
            SOLIPSIST_BORIS_BIN=str(self.binary),
            SPIKE_TEST_CONFIG=str(self.config),
            SPIKE_TEST_CALLS=str(self.calls),
            SPIKE_TEST_FIXTURES=str(FIXTURES),
        )
        self.configure()

    def configure(self, **changes):
        config = dict(
            ids=["guides/getting-started", "index"],
            impact_exit=0,
            impact_report="valid",
            watch_exit=None,
        )
        config.update(changes)
        self.config.write_text(json.dumps(config), encoding="utf-8")

    def run_spike(self, target=None):
        command = [str(SPIKE), str(self.content)]
        if target is not None:
            command.append(target)
        result = subprocess.run(
            command, cwd=self.content.parent, env=self.environment,
            capture_output=True, text=True, timeout=10,
        )
        self.assertNotIn("Fatal error", result.stdout + result.stderr)
        self.assertNotIn("Swift/ErrorType", result.stderr)
        self.assertEqual((self.content / "page.md").read_text(), "untouched authored content")
        return result

    def recorded_calls(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def assert_success_reaches_watch(self, result, expected_target):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("SPIKE OK", result.stdout)
        self.assertIn("serve url", result.stdout)
        self.assertIn("stop exit    : 0", result.stdout)
        calls = self.recorded_calls()
        impact = next(call for call in calls if call[0] == "impact")
        self.assertEqual(impact[1], expected_target)
        self.assertTrue(any(call[0] == "watch" for call in calls))

    def test_namespaced_default_target_reaches_watch(self):
        self.assert_success_reaches_watch(self.run_spike(), "guides/getting-started")

    def test_getting_started_corpus_reaches_watch(self):
        self.configure(ids=["getting-started", "index"])
        self.assert_success_reaches_watch(self.run_spike(), "getting-started")

    def test_explicit_valid_target_reaches_watch(self):
        self.assert_success_reaches_watch(self.run_spike("index"), "index")

    def test_unknown_explicit_target_fails_before_impact(self):
        result = self.run_spike("getting-started")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("not in the supplied graph", result.stderr)
        self.assertFalse(any(call[0] == "impact" for call in self.recorded_calls()))
        self.assertNotIn("SPIKE OK", result.stdout)

    def test_empty_graph_is_a_controlled_content_failure(self):
        self.configure(ids=[])
        result = self.run_spike()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("no pages", result.stderr)
        self.assertFalse(any(call[0] == "impact" for call in self.recorded_calls()))

    def test_missing_impact_report_preserves_nonzero_exit_and_stderr(self):
        self.configure(impact_exit=2, impact_report="missing")
        result = self.run_spike()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("missing expected output artifact: impact report", result.stderr)
        self.assertIn("impact diagnostic", result.stderr)
        self.assertNotIn("SPIKE OK", result.stdout)

    def test_exit_zero_without_an_impact_report_is_not_success(self):
        self.configure(impact_report="missing")
        result = self.run_spike()
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("impact report", result.stderr)
        self.assertNotIn("SPIKE OK", result.stdout)

    def test_malformed_impact_report_is_controlled_and_keeps_stderr(self):
        self.configure(impact_report="malformed")
        result = self.run_spike()
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("failed to decode impact report", result.stderr)
        self.assertIn("impact diagnostic", result.stderr)

    def test_report_without_impact_set_is_not_success(self):
        self.configure(impact_report="no-impact")
        result = self.run_spike()
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("returned no impact set", result.stderr)
        self.assertNotIn("SPIKE OK", result.stdout)

    def test_nonzero_impact_with_a_report_cannot_claim_success(self):
        self.configure(impact_exit=71)
        result = self.run_spike()
        self.assertEqual(result.returncode, 71, result.stderr)
        self.assertIn("impact diagnostic", result.stderr)
        self.assertNotIn("SPIKE OK", result.stdout)

    def test_early_watch_exit_is_controlled_and_does_not_hang(self):
        self.configure(watch_exit=3)
        result = self.run_spike()
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("watch exited before serve-started", result.stderr)
        self.assertNotIn("SPIKE OK", result.stdout)

    def test_exit_zero_before_watch_ready_is_not_success(self):
        self.configure(watch_exit=0)
        result = self.run_spike()
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("watch exited before serve-started", result.stderr)
        self.assertNotIn("SPIKE OK", result.stdout)

    def test_launch_failure_is_controlled(self):
        self.binary.write_text("#!/no/such/interpreter\n", encoding="utf-8")
        result = self.run_spike()
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("launch", result.stderr.lower())


ENGINE_STUB = r'''
import json, os
from pathlib import Path
import shutil, signal, sys, time

args = sys.argv[1:]
config = json.loads(Path(os.environ["SPIKE_TEST_CONFIG"]).read_text())
fixtures = Path(os.environ["SPIKE_TEST_FIXTURES"])
with open(os.environ["SPIKE_TEST_CALLS"], "a") as calls:
    calls.write(json.dumps(args) + "\n")

def option(name):
    return args[args.index(name) + 1]

def emit_report(path, value):
    Path(path).write_text(json.dumps(value))

command = args[0]
if command == "--version":
    print("boris/0.8.1-test-stub")
elif command == "plan":
    print((fixtures / "plan-happy/plan.json").read_text())
elif command == "validate":
    shutil.copyfile(fixtures / "validate-happy/html-build-report.json", option("--report"))
elif command == "--out":
    out = Path(option("--out"))
    for name in ["build-report.json", "manifest.json", "completion.json"]:
        shutil.copyfile(fixtures / "happy-ir" / name, out / name)
    graph = json.loads((fixtures / "happy-ir/graph.json").read_text())
    template = graph["nodes"][0]
    graph["nodes"] = [dict(template, id=page, index=i) for i, page in enumerate(config["ids"])]
    emit_report(out / "graph.json", graph)
elif command in ["check", "impact"]:
    report = json.loads((fixtures / "check-happy/analysis-report.json").read_text())
    if command == "impact":
        print("impact diagnostic", file=sys.stderr)
        report["impact"] = [{"type": "page", "value": args[1]}]
        if config["impact_report"] == "malformed":
            Path(option("--report")).write_text("not JSON")
        elif config["impact_report"] == "valid":
            emit_report(option("--report"), report)
        elif config["impact_report"] == "no-impact":
            report["impact"] = None
            emit_report(option("--report"), report)
        sys.exit(config["impact_exit"])
    emit_report(option("--report"), report)
elif command == "watch":
    if config["watch_exit"] is not None:
        print("watch startup failed", file=sys.stderr, flush=True)
        sys.exit(config["watch_exit"])
    def stop(signum, frame):
        print('{"event":"watch-stopped","reason":"signal"}', file=sys.stderr, flush=True)
        sys.exit(0)
    signal.signal(signal.SIGTERM, stop)
    print('{"event":"hello","watch_events_schema":1}', file=sys.stderr, flush=True)
    print('{"event":"serve-started","helper":"http://127.0.0.1:49152/__boris/","port":49152}', file=sys.stderr, flush=True)
    while True:
        time.sleep(0.02)
else:
    sys.exit(2)
'''


if __name__ == "__main__":
    unittest.main()
