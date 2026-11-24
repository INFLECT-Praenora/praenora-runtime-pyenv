"""The rust engine: viva-core runs a composite."""

import json
import math
import unittest

import support


class RustEngineTest(unittest.TestCase):
    @support.skip_unless_engine("rust")
    def test_viva_core_runs_a_composite(self):
        import viva_core

        spec = {
            "x": 10.0,
            "global_time": 0.0,
            "decay": {
                "_type": "process",
                "address": "local:rust_fixture.Decay",
                "config": {"k": 0.5},
                "interval": 1.0,
                "inputs": {"x": ["x"]},
                "outputs": {"x": ["x"]},
            },
        }
        report = viva_core.run_report(json.dumps(spec), 4)
        state = report["state"]
        self.assertGreater(float(state["global_time"]), 0.0)
        x = float(state["x"])
        self.assertTrue(math.isfinite(x))
        self.assertGreater(x, 0.0)
        self.assertLess(x, 10.0)


if __name__ == "__main__":
    unittest.main()
