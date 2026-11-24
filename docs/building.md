# Building the Python environment

This guide is for developers who build the Python environment bundle of the
[Praenora runtime](https://github.com/INFLECT-Praenora/praenora-runtime) on their own machine. What
the bundle holds, and how the runtime consumes it, is in [outputs.md](outputs.md); the upstreams
and the checks that guard against their changes are in [upstreams.md](upstreams.md); how GitHub
Actions builds the bundles and how they are published is in [releasing.md](releasing.md).

## Requirements

- CMake 3.24 or newer and Ninja: the build tools of the Praenora runtime.
- A C and C++ compiler of one toolchain: AppleClang on macOS (AppleClang 17 is verified), GCC or
  Clang on Linux, MSVC of Visual Studio 2022 on Windows. It compiles BioGears, Xerces-C and the
  extension modules built from source.
- uv 0.11.28 exactly, which locks and installs the Python distributions
  (`PRAENORA_PYENV_UV_EXECUTABLE` names it when it is not on `PATH`).
- Git, to fetch the submodules and to check their commits.
- For the `rust` engine: Rust 1.83 or newer with cargo (rustup; 1.100.0 is verified). On Windows,
  cargo must be on `PATH`.
- For the `biogears` engine: CodeSynthesis XSD (Homebrew `xsd`; Debian and Ubuntu `xsdcxx`), which
  generates BioGears' schema code; on Linux, also patchelf.
- Network access during configuration and the first build: the CPython archive, the distributions
  of `uv.lock` and the git sources it names are downloaded, each checked against the SHA-256 or
  commit that pins it. A second build of the same tree needs no network
  ([Options](#options), `PRAENORA_PYENV_OFFLINE`).

Nothing else is needed: CPython comes from the pinned archive, and no interpreter of the build
machine is used.

## Getting the sources

The upstream sources are submodules under `external/`. Fetch them without history:

```sh
git submodule update --init --depth 1
```

Configuration stops with a message when a submodule is missing or at another commit than its pin.
With the `biogears` engine it also fetches the tag `8.2.0` of `external/biogears`, from which
BioGears takes its version ([upstreams.md](upstreams.md#biogears)).

## Presets

Each preset builds the bundle of one platform into `build/<preset>` and writes it to
`install/<preset>`. Both directories are ignored by git.

| Preset | Platform | Default engines | Status |
|---|---|---|---|
| `macos-arm64-release` | macOS arm64 | tellurium, copasi, biogears, rust | Verified |
| `linux-x64-release` | Linux x86-64 | tellurium, copasi, biogears, rust | Not yet verified |
| `windows-x64-release` | Windows x86-64 | tellurium, copasi, rust | Not yet verified |

Bundles are Release builds only: the interpreter is a release build, and each extension module
carries its own C runtime library.

```sh
cmake --preset macos-arm64-release
cmake --build --preset macos-arm64-release
ctest --preset macos-arm64-release
cmake --build --preset macos-arm64-release --target package
```

On Windows, run the presets from a Visual Studio 2022 developer command prompt for x64.

Measured on a 10-core Apple silicon machine with the default engines, from an empty build tree and
with uv's cache already filled: configuration 6 s, build 4 min 14 s (BioGears most of it), `ctest`
3 min 20 s, archive 79 s. The bundle takes 1.1 GB, its archive 197 MB.

## Options

| Cache variable | Default | Meaning |
|---|---|---|
| `PRAENORA_PYENV_ENGINES` | empty: the platform's default engines | The engines of the bundle, separated by `;`: `tellurium`, `copasi`, `biogears`, `surrogate`, `rust`. `julia` is not available upstream yet, and `biogears` is not supported on Windows; both stop configuration. `surrogate` (PyTorch) is not verified. |
| `PRAENORA_PYENV_OFFLINE` | `OFF` | Every uv call with `--offline`; a missing download is an error. |
| `PRAENORA_PYENV_UV_CACHE_DIR` | `build/<preset>/uv-cache` | uv's cache. Another directory, such as uv's default cache, can be shared between build trees. |
| `CMAKE_INSTALL_PREFIX` | `install/<preset>` | The bundle directory. The build writes the bundle there; there is no separate install step. |
| `CMAKE_OSX_DEPLOYMENT_TARGET` | `14.0` | The oldest macOS for what the build compiles. Prebuilt wheels may need a newer one; the manifest states the highest that any binary of the bundle needs, and `bundle.manifest` fails when it is newer than this target. |
| `CMAKE_C_COMPILER_LAUNCHER`, `CMAKE_CXX_COMPILER_LAUNCHER` | empty | Passed to the BioGears, Xerces-C and Eigen builds. |

## What the build does

1. **Configuration** checks the submodules against their pins, the revisions of the git sources
   that this repository and inflect-sim-core both pin, the engines and their tools, downloads and
   unpacks the CPython archive into `build/<preset>/python-stage`, and runs `uv lock --check`,
   which stops the configuration when `uv.lock` does not match `pyproject.toml` or
   `external/inflect-sim-core`.
2. **CPython** (`pyenv_interpreter`) is copied into `<bundle>/python`.
3. **BioGears** (with `biogears`): Eigen, Xerces-C and BioGears 8.2.0 are built from their
   submodules into work prefixes in `build/<preset>/work`, with the options of pybiogears' own
   build script (no tools, tests, examples or website; Boost not used). Xerces-C is built without
   network access or ICU, so that it needs only the system's libraries. A script
   (`cmake/praenora_pyenv_biogears_bundle.cmake`) copies BioGears' and Xerces-C's shared libraries
   into `<bundle>/biogears/lib`, with load paths relative to themselves, and BioGears' data into
   `<bundle>/biogears/share/biogears/runtime`.
4. **The Python environment** (`pyenv_environment`): `uv sync --frozen` installs the distributions
   of `uv.lock` for the enabled engines into the bundle's interpreter, without resolving anything.
   simulation-core is reinstalled from its submodule each time, and pybiogears is rebuilt with
   BioGears; a new submodule commit installs the environment again and rebuilds BioGears, Xerces-C
   or Eigen. uv builds the git and path sources (inflect-sim-core, the viva-* wrappers, viva-core with
   maturin and Rust, pybiogears against BioGears) with the build backends that `pyproject.toml`
   pins, the project's compilers and its macOS deployment target.
5. **The bundle step** (`pyenv_bundle`, `cmake/PraenoraPyenvBundle.cmake`) stops when a
   distribution has another version than `PRAENORA_PYENV_EXPECTED_VERSIONS`, when an excluded
   distribution is installed, or when a distribution ships no license file and is not on
   `PRAENORA_PYENV_LICENSE_ALLOWLIST`. It copies the license files into `licenses/`, makes the
   bundle relocatable (console scripts find the interpreter beside them; metadata files that name
   the build machine are removed; pybiogears finds BioGears relative to itself), measures the
   oldest macOS that every binary supports, and writes the manifest and the CMake package.

The target `package` builds everything, then archives the bundle with CPack.

## Checking a bundle

`ctest --preset <preset>` runs these tests:

- `config.submodules` and `config.engines`: the submodule check and the engine selection, on
  inputs of their own.
- `python.unittest`: the tests of `tests/python`, run by the bundle's interpreter in isolated mode.
  Every module of `viva_simulation_core` imports, except those of engines that are not enabled;
  the excluded distributions are absent; the manifest's environment keeps a caller's `PYTHONPATH`
  out; the engine list of inflect-sim-core equals the table of
  `cmake/PraenoraPyenvEngines.cmake`, and the installed engines are the enabled ones; the entry
  points that the runtime will use exist; each enabled engine runs a model: tellurium and COPASI a
  rate-rule model against its exact solution, BioGears the `sepsis_engine` composite with finite
  vitals, viva-core a composite of the tests' own. One test is an expected failure that tracks a
  known upstream issue ([upstreams.md](upstreams.md#known-upstream-issues)).
- `bundle.manifest`: the manifest agrees with the build, every file it lists exists, every
  distribution has license files or is on the allow-list, the distributions built from the
  submodules are recorded as `local`, the installed `viva_simulation_core` equals the submodule's,
  `platform.os_min_version` is not newer than `CMAKE_OSX_DEPLOYMENT_TARGET`, and no file that a
  consumer reads names the build or source tree.
- `bundle.embed`: a program that embeds the bundle's CPython, built with the bundle as its only
  prefix ([outputs.md](outputs.md#embedding)), runs a simulation with `PYTHONPATH` and `PYTHONHOME`
  set and a `workspace.yaml` in its current directory, and writes no bytecode into the bundle. The CMake package refuses a newer
  version, another operating system or architecture, an older macOS deployment target and an
  engine that the bundle does not hold.
- `bundle.relocated`: the bundle copied to a path with a space and a non-ASCII character; no binary
  names the original location or the build tree (macOS), and the Python checks and the embedding
  program pass there.
- `tools.drift`: the drift report ([upstreams.md](upstreams.md#the-drift-report)) against git
  repositories of the test's own.
- `docs.consistency`: the links of the documentation resolve, and no file names a path on a
  developer's machine.

## Updating an upstream

The submodule commit, its pin in `cmake/PraenoraPyenvVersions.cmake`, `uv.lock`, the expected
versions and the bundle's version change together. For a new inflect-sim-core commit:

1. Check out the commit in the submodule:

   ```sh
   git -C external/inflect-sim-core fetch --depth 1 origin <commit>
   git -C external/inflect-sim-core checkout <commit>
   ```

2. Set `PRAENORA_PYENV_INFLECT_SIM_CORE_REF` and `_COMMIT`. When inflect-sim-core's
   `[tool.uv.sources]` names other revisions of viva-superpowers or viva-workspace, use them in
   `PRAENORA_PYENV_VIVA_SOURCES` and in `pyproject.toml`.
3. Re-lock with the bundle's interpreter, and review the change of `uv.lock`:

   ```sh
   uv lock --python build/macos-arm64-release/python-stage/python/bin/python3.12
   git diff uv.lock
   ```

   A new git or path source may need its build backend in `build-constraint-dependencies`.
4. When inflect-sim-core moves viva-biogears to another commit, move `external/pybiogears` to the
   commit that matches it; a pair that does not match returns NaN, which `python.unittest` detects.
5. Build and run `ctest`. Update `PRAENORA_PYENV_EXPECTED_VERSIONS` with the versions the bundle
   step reports, the engine table when inflect-sim-core's engine list changed, and the allow-list
   when a new distribution ships no license file and its license allows publishing.
6. Raise the bundle's version in `CMakeLists.txt` and `pyproject.toml`
   ([outputs.md](outputs.md#versions)), update the tables of [README.md](../README.md) and
   [upstreams.md](upstreams.md), then stage the submodule and the files together.

Never commit changes inside a submodule's working tree: the manifest records an upstream whose
working tree differs from its commit as `modified`, and the workflow refuses it.

## Platform notes

- **macOS.** The bundle's binaries need the macOS version that the manifest states
  (`platform.os_min_version`), 14.0 for the verified bundle; a consumer's deployment target must be
  at least that version. The measurement leaves out the binaries that
  `PRAENORA_PYENV_OS_MIN_VERSION_IGNORE` names, with the reason: debugpy's helper for attaching its
  debugger to another process, which targets macOS 15.0 and is not loaded to simulate.
- **Linux.** Not yet verified. The bundle runs on the distribution it was built on
  (`platform.distribution`) or a newer one. patchelf makes BioGears' and pybiogears' load paths
  relative.
- **Windows.** Not yet verified. Without `biogears`. cargo must be on `PATH` before configuring.
