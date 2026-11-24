"""tools/upstream_drift.py against git repositories of the test's own, without network access."""

import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

TOOL = pathlib.Path(__file__).resolve().parents[2] / "tools" / "upstream_drift.py"

PYPROJECT = """[project]
name = "simulation-core"
version = "0.0.0"
dependencies = [
    "pyyaml>=6.0",
]

[project.optional-dependencies]
tellurium = ["viva-tellurium @ git+https://example.invalid/viva-tellurium@1111"]

[tool.uv.sources]
viva-superpowers = { git = "https://example.invalid/viva-superpowers.git", rev = "aaaa" }
"""

ENGINES = """_ENGINES: dict[str, tuple[str, str, str]] = {
    "tellurium": ("viva_tellurium", "tellurium", "Tellurium"),
    "julia": ("viva_julia_diffeqs", "julia", "Julia"),
}
"""


def git(repository, *arguments):
    return subprocess.run(
        ["git", "-C", str(repository), "-c", "user.name=test", "-c", "user.email=test@invalid",
         "-c", "commit.gpgsign=false", *arguments],
        check=True, capture_output=True, text=True).stdout.strip()


class DriftTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="praenora-pyenv-drift-")
        self.root = pathlib.Path(self.directory.name)
        self.upstream = self.root / "inflect-sim-core"
        (self.upstream / "viva_simulation_core").mkdir(parents=True)
        git(self.root, "init", "-q", "--template=", "-b", "main", str(self.upstream))
        self.write(PYPROJECT, ENGINES)
        self.pin = self.commit("first")

    def tearDown(self):
        self.directory.cleanup()

    def write(self, pyproject, engines):
        (self.upstream / "pyproject.toml").write_text(pyproject, encoding="utf-8")
        (self.upstream / "viva_simulation_core" / "engines.py").write_text(engines,
                                                                           encoding="utf-8")

    def commit(self, message):
        git(self.upstream, "add", "-A")
        git(self.upstream, "commit", "-q", "-m", message)
        return git(self.upstream, "rev-parse", "HEAD")

    def run_tool(self, repository=None):
        pins = self.root / "pins.cmake"
        url = repository or self.upstream.as_uri()
        pins.write_text(
            "set(PRAENORA_PYENV_UPSTREAMS inflect-sim-core)\n"
            f'set(PRAENORA_PYENV_INFLECT_SIM_CORE_REPOSITORY "{url}")\n'
            f'set(PRAENORA_PYENV_INFLECT_SIM_CORE_COMMIT "{self.pin}")\n'
            'set(PRAENORA_PYENV_INFLECT_SIM_CORE_BRANCH "main")\n', encoding="utf-8")
        environment = dict(os.environ, GIT_TERMINAL_PROMPT="0")
        return subprocess.run([sys.executable, str(TOOL), "--pins", str(pins)],
                              capture_output=True, text=True, env=environment)

    def test_no_drift_when_heads_match_pins(self):
        result = self.run_tool()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("no drift", result.stdout)

    def test_reports_new_dependency(self):
        self.write(PYPROJECT.replace('"pyyaml>=6.0",', '"pyyaml>=6.0",\n    "six",'), ENGINES)
        self.commit("add six")
        result = self.run_tool()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("inflect-sim-core", result.stdout)
        self.assertIn("+ six", result.stdout)
        self.assertIn("add six", result.stdout)

    def test_reports_engine_added(self):
        self.write(PYPROJECT, ENGINES.replace(
            "}\n", '    "julia2": ("viva_julia2", "julia2", "Julia 2"),\n}\n'))
        self.commit("add julia2")
        result = self.run_tool()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("engine added: julia2", result.stdout)

    def test_reports_source_revision_change(self):
        self.write(PYPROJECT.replace('rev = "aaaa"', 'rev = "bbbb"'), ENGINES)
        self.commit("move viva-superpowers")
        result = self.run_tool()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("viva-superpowers", result.stdout)
        self.assertIn("aaaa", result.stdout)
        self.assertIn("bbbb", result.stdout)

    def test_unreachable_repository_is_an_error(self):
        result = self.run_tool((self.root / "missing").as_uri())
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("inflect-sim-core", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
