"""The biogears engine: BioGears runs inflect-sim-core's sepsis_engine composite."""

import math
import os
import pathlib
import unittest

import support


class BiogearsEngineTest(unittest.TestCase):
    @support.skip_unless_engine("biogears")
    def test_biogears_runtime_directory_is_in_the_bundle(self):
        runtime = pathlib.Path(os.environ["BIOGEARS_RUNTIME"]).resolve()
        self.assertTrue(runtime.is_relative_to(support.bundle_dir().resolve()), runtime)
        self.assertTrue((runtime / "states" / "StandardMale@0s.xml").is_file())

    @support.skip_unless_engine("biogears")
    def test_sepsis_engine_composite_has_finite_vitals(self):
        # The composite is not registered for simulate(); it is built as inflect-sim-core's own
        # tests build it. A viva-biogears and pybiogears pair that does not match returns NaN.
        from process_bigraph import Composite, gather_emitter_results
        from viva_biogears.core import build_core
        from viva_simulation_core.composites.sepsis_engine import (
            extract_observables, make_sepsis_engine_composite)

        core = build_core()
        doc = make_sepsis_engine_composite(severity=0, horizon_s=120.0, interval_s=60.0,
                                           core=core)
        simulation = Composite({"state": doc}, core=core)
        simulation.run(120.0)
        observables = extract_observables(gather_emitter_results(simulation)[("emitter",)])
        self.assertTrue(observables)
        for name, values in observables.items():
            with self.subTest(observable=name):
                self.assertGreaterEqual(len(values), 2)
                self.assertTrue(all(math.isfinite(value) for value in values), values)


if __name__ == "__main__":
    unittest.main()
