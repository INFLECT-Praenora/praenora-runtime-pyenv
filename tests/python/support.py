"""What the bundle's Python tests share: the bundle under test, its engines and the test models.

The CTest test python.unittest runs these tests with the bundle's interpreter in isolated mode
(-I) and sets PRAENORA_PYENV_BUNDLE (the bundle directory), PRAENORA_PYENV_ENGINES (its engines,
separated by ';') and, with BioGears, BIOGEARS_RUNTIME.
"""

import math
import os
import pathlib
import tempfile
import unittest

# Matplotlib, which process-bigraph imports, needs a writable configuration directory.
os.environ.setdefault("MPLCONFIGDIR", tempfile.mkdtemp(prefix="praenora-pyenv-mpl-"))

# A parameter with a rate rule: A(t) = 10 exp(-0.5 t).
RATE_MODEL = "model m\n  A' = -k*A\n  A = 10; k = 0.5\nend"

# The same decay as a reaction of a species.
SPECIES_MODEL = "model m\n  J0: A -> ; k*A\n  A = 10; k = 0.5\nend"

# Modules of viva_simulation_core that import only with an engine (the value) that a bundle may
# leave out. A key names a module and its submodules.
OPTIONAL_MODULES = {
    # Imports viva_superpowers, which the biogears extra brings.
    "viva_simulation_core.capability_cards": "biogears",
    # The learned surrogate imports torch.
    "viva_simulation_core.surrogate": "surrogate",
}


def exact(t):
    """The solution of RATE_MODEL and SPECIES_MODEL at time t."""
    return 10.0 * math.exp(-0.5 * t)


def bundle_dir():
    """The bundle under test."""
    return pathlib.Path(os.environ["PRAENORA_PYENV_BUNDLE"])


def enabled_engines():
    """The bundle's engines."""
    return [name for name in os.environ.get("PRAENORA_PYENV_ENGINES", "").split(";") if name]


def skip_unless_engine(name):
    """Skips a test when the bundle does not hold the engine `name`."""
    return unittest.skipUnless(name in enabled_engines(), f"engine not enabled: {name}")


def optional_engine(module):
    """The engine that `module` needs, or None when it needs none."""
    for prefix, engine in OPTIONAL_MODULES.items():
        if module == prefix or module.startswith(prefix + "."):
            return engine
    return None
