# Upstreams

The bundle is built from upstream projects that change often and without announcement. This
document lists each upstream, how it is pinned, the checks that stop a build or a test when it
changes in a way that affects the bundle, and what is known about it. How to update a pin is in
[building.md](building.md#updating-an-upstream).

## Pins

| Upstream | Pinned at | How |
|---|---|---|
| [inflect-sim-core](https://github.com/INFLECT-Praenora/inflect-sim-core) | commit `9a10a27` (`main`; no tags or releases exist) | submodule `external/inflect-sim-core` |
| [BioGears](https://github.com/BioGearsEngine/core) | tag `8.2.0` (`c5227b6`) | submodule `external/biogears` |
| [pybiogears](https://github.com/vivarium-collective/pybiogears) | commit `01db2ef` (`main`; untagged) | submodule `external/pybiogears` |
| [Xerces-C](https://github.com/apache/xerces-c) | tag `v3.3.0` | submodule `external/xerces-c` |
| [Eigen](https://gitlab.com/libeigen/eigen) | tag `3.4.0` | submodule `external/eigen` |
| CPython 3.12.16 | python-build-standalone release `20261123` | archive URL and SHA-256 per platform |
| Python distributions | exact versions, with hashes; git sources by commit | `uv.lock`, from `pyproject.toml` |
| Build backends | hatchling, maturin, pybind11, scikit-build-core, setuptools, wheel, and packaging, pathspec, pluggy, trove-classifiers, which they require | `build-constraint-dependencies` in `pyproject.toml` |
| uv | 0.11.28 | `required-version` in `pyproject.toml`, checked at configuration |

`cmake/PraenoraPyenvVersions.cmake` holds the pins; the git sources of inflect-sim-core's engines
(viva-tellurium, viva-copasi, viva-biogears, viva-core) are pinned by commit in inflect-sim-core's
own `pyproject.toml`, and `uv.lock` records them.

## Guards

Each guard stops the configuration, the build or a test, with a message that names the change:

| Change upstream | Guard |
|---|---|
| A submodule at another commit, or missing | Configuration (`praenora_pyenv_check_upstream`); the new commit installs the environment again and rebuilds what is built from it. |
| inflect-sim-core's code changes | `bundle.manifest` compares the installed `viva_simulation_core` with the submodule. |
| Tracked files of a submodule changed | The manifest records `modified`; the workflow refuses the bundle. |
| inflect-sim-core's dependencies or extras change | `uv lock --check` at configuration: the lock no longer matches. |
| inflect-sim-core pins other revisions of viva-superpowers or viva-workspace | Configuration compares them with `PRAENORA_PYENV_VIVA_SOURCES`. |
| A distribution's version changes | The bundle step compares it with `PRAENORA_PYENV_EXPECTED_VERSIONS`. |
| An excluded distribution comes back | The bundle step and `python.unittest`. |
| A distribution without license files appears | The bundle step, unless it is on `PRAENORA_PYENV_LICENSE_ALLOWLIST`. |
| inflect-sim-core's code starts importing a package the bundle lacks | `python.unittest` imports every module of `viva_simulation_core`. |
| inflect-sim-core adds, removes or renames an engine | `python.unittest` compares `known_engines()` with the engine table. |
| The entry points change | `python.unittest` checks `simulate`, `SimulationRequest`, `SimulationResult`, `VerificationReport`, `catalog`, `call`, `connect`, `run`. |
| An engine stops working, or returns non-finite values | `python.unittest` runs a model with each enabled engine. |
| Upstream branches move before a pin does | [The drift report](#the-drift-report). |

## inflect-sim-core

The bundle holds its simulation capability: the package `viva_simulation_core` and the engines
that its extras install. Not included: the workbench, dashboards, reports, investigations and
studies, the extras `serve` and `dev`, and inflect-models-db.

### Excluded distributions

inflect-sim-core requires `vivarium-workbench` (a web dashboard with FastAPI, boto3, zarr and other
packages) and `bigraph-viz` for its workbench and reports, and viva-biogears requires
`vivarium-workbench` too. `pyproject.toml` removes both from every resolution through
`override-dependencies`; `PRAENORA_PYENV_EXCLUDED_DISTRIBUTIONS` lists them. Other packages that
inflect-sim-core lists for reports (plotly, jinja2, pypdf) stay, because tellurium or
viva-superpowers requires them.

### Engines

| Engine | Extra | Built from source | Default |
|---|---|---|---|
| `tellurium` | tellurium (viva-tellurium, tellurium, libroadrunner) | viva-tellurium | yes |
| `copasi` | copasi (viva-copasi, python-copasi, copasi-basico) | viva-copasi | yes |
| `biogears` | biogears (viva-biogears, viva-superpowers, pybiogears) | BioGears, Xerces-C, pybiogears | yes, not on Windows |
| `rust` | rust (viva-core) | viva-core (Rust) | yes |
| `surrogate` | surrogate (viva-torch, PyTorch) | viva-torch | no; not verified |
| `julia` | none upstream yet | | not available |

`cmake/PraenoraPyenvEngines.cmake` holds the table. Adding an engine takes a row there, an extra in
`pyproject.toml`, a re-lock and a check in `tests/python`.

Unsupported parts of inflect-sim-core: the demonstration composites that read files from its
`workspace/` directory, such as `sepsis_sbml` (the bundle does not hold that directory), and
`capability_cards` without the biogears engine, which brings viva-superpowers.

### Known upstream issues

- **COPASI species values.** inflect-sim-core's COPASI runner reports species as particle numbers,
  not concentrations. The test `test_copasi_species_match_exact_solution` is an expected failure;
  when upstream fixes it, the test fails as an unexpected success, and the decorator and this note
  are removed.
- **viva-core has no `Cargo.lock`.** cargo resolves its crates when it builds them, so a build may
  download newer crate versions.

## BioGears

The `biogears` engine runs BioGears 8.2.0 through pybiogears, built against it, and viva-biogears.

- BioGears takes its version from `git describe --tags`; configuration fetches the tag `8.2.0` into
  the submodule when it is missing.
- viva-biogears imports viva-superpowers, which inflect-sim-core otherwise gets only through the
  workbench; the `biogears` extra adds it at the revision that inflect-sim-core pins.
- pybiogears and viva-biogears must match: a pair that does not match returns NaN, which
  `python.unittest` detects. When inflect-sim-core moves viva-biogears, pybiogears moves to the
  commit that matches it.
- The build reproduces what pybiogears' `scripts/install_biogears.sh` does after installing
  BioGears (generated schema headers, the data directory, load paths on macOS), in CMake.
- Not supported on Windows: pybiogears' build script covers macOS and Linux only, and
  CodeSynthesis XSD has no package on the Windows runner.

## The drift report

`tools/upstream_drift.py` compares the head of each upstream that follows a branch (inflect-sim-core
and pybiogears, `PRAENORA_PYENV_<UP>_BRANCH`) with its pin, and reports the new commits and the
changes of inflect-sim-core's dependencies, extras, `[tool.uv.sources]` and engines. It builds
nothing and changes no pin.

```sh
install/macos-arm64-release/python/bin/python3.12 tools/upstream_drift.py
```

It exits with 0 when no upstream moved, 1 when one did, and 2 when one could not be read. The
workflow runs it every Monday ([releasing.md](releasing.md#the-workflow)); a failed run means that
an upstream moved, and a maintainer decides whether to update its pin.
