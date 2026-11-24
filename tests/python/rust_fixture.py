"""A process for the check of the rust engine (viva-core), which runs processes by address."""

from process_bigraph import Process, allocate_core


class Decay(Process):
    """x decreases at the rate k*x.

    viva-core creates a Python process as cls(config), without a core; process-bigraph's Process
    needs one, so the process makes its own when none is given.
    """

    config_schema = {"k": "float"}

    def __init__(self, config=None, core=None):
        super().__init__(config, core if core is not None else allocate_core())

    def inputs(self):
        return {"x": "float"}

    def outputs(self):
        return {"x": "float"}

    def update(self, state, interval):
        return {"x": -self.config["k"] * state["x"] * interval}
