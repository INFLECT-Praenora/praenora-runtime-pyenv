# AGENTS.md

Guide for coding agents and human contributors working in `praenora-runtime-pyenv`. Read it before
changing anything.

## Purpose

This repository builds the managed Python environment of the
[Praenora runtime](https://github.com/INFLECT-Praenora/praenora-runtime) and packages it as a
bundle that the runtime's build can consume: a relocatable, embeddable CPython 3.12 with the
simulation capability of [inflect-sim-core](https://github.com/INFLECT-Praenora/inflect-sim-core)
and its engines (tellurium, copasi, biogears, rust by default), for runtime services and modules
that use Python packages. It is developed and released like
[praenora-runtime-deps](https://github.com/INFLECT-Praenora/praenora-runtime-deps). The upstream
sources are git submodules and a committed `uv.lock`; this repository holds only the build, the
packaging, the checks, the workflow, the drift report and the documentation.

Producing bundles that the Praenora runtime can consume takes priority over every other goal.

## Status

Verified on macOS arm64 with AppleClang 17 and CPython 3.12.16: the build with the default engines,
all checks of `ctest`, and the archive. The Linux and Windows presets are written but not yet
verified. The GitHub Actions workflow (`.github/workflows/build.yml`) is written but has not yet
passed (not yet verified); no release has been published. The Praenora runtime does not consume the
bundles yet.

## Setup and commands

Requirements: CMake 3.24+, Ninja, uv 0.11.28, Git, a C and C++ compiler of one toolchain; Rust 1.83+
for the `rust` engine; CodeSynthesis XSD (and patchelf on Linux) for the `biogears` engine. Details
are in [docs/building.md](docs/building.md).

```sh
git submodule update --init --depth 1               # the upstream sources, without history
cmake --preset macos-arm64-release                  # or linux-x64-release, windows-x64-release
cmake --build --preset macos-arm64-release          # builds the bundle into install/<preset>
ctest --preset macos-arm64-release                  # config.*, python.unittest, bundle.*, ...
cmake --build --preset macos-arm64-release --target package   # build/<preset>/package/*.tar.xz
uv lock --python build/<preset>/python-stage/python/bin/python3.12   # re-lock after a change
install/<preset>/python/bin/python3.12 tools/upstream_drift.py       # upstream drift report
```

Build trees go to `build/<preset>`, bundles to `install/<preset>`.

## Repository map

```
LICENSE                 MIT license of this repository's files
CMakeLists.txt          superbuild: project(VERSION) is the bundle's version
CMakePresets.json       {linux-x64,macos-arm64,windows-x64}-release
pyproject.toml          the environment's definition (uv project, package = false): engines as
                        extras, excluded distributions, pinned build backends
uv.lock                 the committed lock, for the three platforms
cmake/
  PraenoraPyenvVersions.cmake     pins: CPython archives, uv, Rust minimum, submodules, git
                                  sources, excluded distributions, expected versions, license
                                  allow-list; manifest format version
  PraenoraPyenvPlatform.cmake     OS, architecture, compiler and Python labels; bundle name
  PraenoraPyenvUpstreams.cmake    submodule, source-revision and tag checks
  PraenoraPyenvEngines.cmake      the engine table and the engine selection
  PraenoraPyenvTools.cmake        uv, Rust and CodeSynthesis XSD; the lock check
  PraenoraPyenvInterpreter.cmake  the CPython archive: download, check, unpack
  PraenoraPyenvEnvironment.cmake  the interpreter in the bundle and uv sync
  PraenoraPyenvNative.cmake       Eigen, Xerces-C and BioGears (external projects)
  PraenoraPyenvPackage.cmake      the bundle step target and CPack
  PraenoraPyenvBundle.cmake       the bundle step (script): checks, licenses, relocation,
                                  manifest, CMake package
  praenora_pyenv_*.cmake          scripts: copying a tree with its links, BioGears into the bundle
  PraenoraRuntimePyenvConfig.cmake.in, PraenoraRuntimePyenvConfigVersion.cmake.in
tests/                  config.* (check_submodules, check_engines), python/ (python.unittest),
                        check_manifest.cmake, embed/ and run_embed.cmake, run_relocated.cmake,
                        tools/ (tools.drift), check_docs.cmake
tools/upstream_drift.py the drift report (not part of the build)
external/               submodules: inflect-sim-core, biogears, pybiogears, xerces-c, eigen
.github/workflows/
  build.yml             builds, checks and archives the bundles; drafts a release on request;
                        the weekly drift report
docs/                   building.md, outputs.md, upstreams.md, releasing.md
```

## Conventions

- **Build tools.** CMake (3.24+, presets version 5), Ninja, CTest and CPack drive the build; uv,
  at a fixed version, locks and installs the Python distributions. What the build does stays in
  CMake; Python serves the checks (`tests/python`, `tests/tools`) and the drift report.
- **Workflow.** One GitHub Actions workflow, `.github/workflows/build.yml`. Runner labels name
  fixed image versions, never `-latest`, and actions are pinned to commits.
- **CMake style.** Four-space indentation, lines of at most 100 characters, lowercase commands.
  Variables of this project start with `PRAENORA_PYENV_`; functions and macros with
  `praenora_pyenv_` (`_praenora_pyenv_` when internal to one file). Each file under `cmake/`
  starts with a comment that says what it does and what it defines. Every `execute_process()`
  gives `ENCODING UTF-8`.
- **Python.** CPython 3.12 conventions of the Praenora runtime: tests are stdlib `unittest`
  modules `tests/python/test_*.py` (classes `<Topic>Test`, methods `test_<what>`), with shared
  helpers in `tests/python/support.py`, run by the bundle's interpreter in isolated mode.
- **Labels.** Platform names are the Praenora runtime's: `linux`, `macos`, `windows`; `x86_64`,
  `arm64`. No field of the bundle name contains `-`.
- **Text.** UTF-8 and LF line endings. Documentation is concise and factual: plain sentences, no
  idioms or figurative language. Mark anything not verified as "not yet verified". Documents refer
  to other repositories by their URLs and by paths inside them, never by a path on a local machine.

## Change rules

- **Upstream updates.** A submodule commit, its pins, `uv.lock`, the expected versions, the
  bundle's version and the documentation change together
  ([docs/building.md](docs/building.md#updating-an-upstream)). Review every change of `uv.lock`.
- **Engines.** An engine is added or removed in `cmake/PraenoraPyenvEngines.cmake`,
  `pyproject.toml`, `tests/python` and [docs/upstreams.md](docs/upstreams.md#engines) together.
- **Licenses.** This repository's files are under the MIT license (`LICENSE`). What a bundle holds
  keeps its upstream licenses; a distribution without license files enters
  `PRAENORA_PYENV_LICENSE_ALLOWLIST` only after its license is checked
  ([docs/outputs.md](docs/outputs.md#licenses)).
- **Versions.** Raise the bundle's version in `CMakeLists.txt` and `pyproject.toml` with every
  change to what a consumer gets ([docs/outputs.md](docs/outputs.md#versions)). Raise
  `PRAENORA_PYENV_MANIFEST_VERSION` when a manifest member is removed or changes meaning.
- **Consumers.** The layout, the manifest members and the CMake package's variables are an
  interface for the Praenora runtime's build. Change them only together with
  [docs/outputs.md](docs/outputs.md).
- **Releases.** Bundles are published only as releases that the workflow drafts from `main` and an
  administrator publishes ([docs/releasing.md](docs/releasing.md)).
- **Verification.** Before reporting a change as done, build the bundle and run `ctest`.
- **Documentation.** A change updates its code, checks and documentation together.

## Prohibitions

- No changes inside `external/`: the bundle is built from upstream commits only.
- No resolution of dependency versions during a build: every download is pinned by SHA-256 or
  commit (`uv sync --frozen`).
- Never commit build trees, bundles, archives or `CMakeUserPresets.json`.
- No release, tag `v*` or release asset made by hand.
- Agent instructions live in this file only.
