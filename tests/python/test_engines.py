"""The engine list of inflect-sim-core, its entry points, and a simulation with each SBML engine."""

import dataclasses
import unittest

import support
import viva_simulation_core
from viva_simulation_core import engines


class EngineListTest(unittest.TestCase):
    def test_known_engines_match_the_table(self):
        # The table of cmake/PraenoraPyenvEngines.cmake, in the same order.
        self.assertEqual(engines.known_engines(),
                         ["tellurium", "copasi", "biogears", "surrogate", "rust", "julia"])

    def test_available_engines_are_the_enabled_ones(self):
        self.assertEqual(sorted(engines.available_engines()), sorted(support.enabled_engines()))


class ContractTest(unittest.TestCase):
    def test_entry_points_exist(self):
        for name in ("simulate", "SimulationRequest", "SimulationResult", "VerificationReport",
                     "catalog", "call", "connect", "run"):
            with self.subTest(name=name):
                self.assertTrue(hasattr(viva_simulation_core, name))

    def test_request_fields(self):
        fields = {field.name for field in
                  dataclasses.fields(viva_simulation_core.SimulationRequest)}
        self.assertLessEqual({"duration", "interval", "observables", "engine", "model_format"},
                             fields)


class SbmlEngineTest(unittest.TestCase):
    def simulate(self, engine, model):
        return viva_simulation_core.simulate(model, duration=4, interval=1, observables=["A"],
                                             engine=engine, model_format="antimony")

    def assert_exact(self, values):
        self.assertEqual(len(values), 5)
        for t, value in enumerate(values):
            self.assertAlmostEqual(value / support.exact(t), 1.0, delta=1e-5, msg=f"t={t}")

    @support.skip_unless_engine("tellurium")
    def test_tellurium_matches_exact_solution(self):
        out = self.simulate("tellurium", support.RATE_MODEL)
        self.assertTrue(out.verification.passed)
        self.assert_exact(out.results["A"])

    @support.skip_unless_engine("copasi")
    def test_copasi_matches_exact_solution(self):
        out = self.simulate("copasi", support.RATE_MODEL)
        self.assertTrue(out.verification.passed)
        self.assert_exact(out.results["A"])

    # inflect-sim-core's COPASI runner reports species as particle numbers, not concentrations
    # (docs/upstreams.md#known-upstream-issues). When upstream fixes it, this test fails as an
    # unexpected success; then remove the decorator and the note.
    @unittest.expectedFailure
    @support.skip_unless_engine("copasi")
    def test_copasi_species_match_exact_solution(self):
        out = self.simulate("copasi", support.SPECIES_MODEL)
        self.assert_exact(out.results["A"])


if __name__ == "__main__":
    unittest.main()
