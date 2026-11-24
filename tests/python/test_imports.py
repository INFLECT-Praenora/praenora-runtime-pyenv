"""The bundle's interpreter, its distributions, and the modules of inflect-sim-core."""

import importlib
import importlib.metadata
import json
import os
import pathlib
import pkgutil
import subprocess
import sys
import tempfile
import unittest

import support


class ImportsTest(unittest.TestCase):
    def test_python_is_the_bundled_interpreter(self):
        self.assertEqual(sys.version_info[:3], (3, 12, 16))
        prefix = pathlib.Path(sys.prefix).resolve()
        self.assertTrue(prefix.is_relative_to(support.bundle_dir().resolve()), prefix)

    def test_every_module_imports(self):
        import viva_simulation_core

        failures = []

        def record(name):
            failures.append(f"{name}: {sys.exc_info()[1]!r}")

        for module in pkgutil.walk_packages(viva_simulation_core.__path__,
                                            "viva_simulation_core.", onerror=record):
            engine = support.optional_engine(module.name)
            if engine is not None and engine not in support.enabled_engines():
                continue
            try:
                importlib.import_module(module.name)
            except Exception as error:  # every failure is reported, not only the first
                failures.append(f"{module.name}: {error!r}")
        self.assertEqual(failures, [])

    def test_manifest_environment_keeps_pythonpath_out(self):
        # A process that runs the bundle's Python with the manifest's environment imports the
        # bundle's modules, whatever PYTHONPATH and the current directory hold.
        bundle = support.bundle_dir()
        manifest = json.loads((bundle / "praenora-runtime-pyenv.json").read_text("utf-8"))
        with tempfile.TemporaryDirectory() as shadow:
            pathlib.Path(shadow, "viva_simulation_core.py").write_text(
                "raise ImportError('PYTHONPATH reached the interpreter')\n", encoding="utf-8")
            environment = dict(os.environ, PYTHONPATH=shadow)
            for name, path in manifest["environment"]["paths"].items():
                environment[name] = str(bundle / path)
            environment.update(manifest["environment"]["values"])
            # The bundle's path may hold non-ASCII characters.
            environment["PYTHONIOENCODING"] = "utf-8"
            result = subprocess.run(
                [sys.executable, "-c",
                 "import viva_simulation_core; print(viva_simulation_core.__file__)"],
                env=environment, cwd=shadow, capture_output=True, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stderr)
        module = pathlib.Path(result.stdout.strip()).resolve()
        self.assertTrue(module.is_relative_to(bundle.resolve()), module)

    def test_excluded_distributions_are_absent(self):
        for name in ("vivarium-workbench", "bigraph-viz"):
            with self.subTest(name=name):
                with self.assertRaises(importlib.metadata.PackageNotFoundError):
                    importlib.metadata.distribution(name)


if __name__ == "__main__":
    unittest.main()
