# praenora-runtime-pyenv

Builds the managed Python environment of the
[Praenora runtime](https://github.com/INFLECT-Praenora/praenora-runtime): a relocatable CPython 3.12
that holds the simulation capability of
[inflect-sim-core](https://github.com/INFLECT-Praenora/inflect-sim-core) and its simulation engines,
for runtime services and modules that use Python packages. The build produces a bundle: one
directory, and optionally one archive, with the interpreter (embeddable, with libpython and its
headers), the installed distributions, what the engines need at run time, the license files, a
manifest and a CMake package that state the bundle's version, platform, Python ABI, compiler and
engines. Its upstreams are pinned by submodule commits and a committed `uv.lock`, and checks stop a
build when they change ([docs/upstreams.md](docs/upstreams.md)). GitHub Actions builds the bundles
for Linux x86-64, macOS arm64 and Windows x86-64, and releases of this repository publish them
([docs/releasing.md](docs/releasing.md)).

| Component | Upstream | Pinned | Bundle directory |
|---|---|---|---|
| CPython 3.12.16 | [python-build-standalone](https://github.com/astral-sh/python-build-standalone) | `20261123` | `python/` |
| inflect-sim-core (`simulation-core`) | [INFLECT-Praenora/inflect-sim-core](https://github.com/INFLECT-Praenora/inflect-sim-core) | `9a10a27` | `python/` (site-packages) |
| Engines tellurium, copasi, rust | viva-tellurium, viva-copasi, viva-core (pinned by inflect-sim-core) | `uv.lock` | `python/` (site-packages) |
| Engine biogears: BioGears 8.2.0 | [BioGearsEngine/core](https://github.com/BioGearsEngine/core) | `8.2.0` | `biogears/` |
| pybiogears | [vivarium-collective/pybiogears](https://github.com/vivarium-collective/pybiogears) | `01db2ef` | `python/` (site-packages) |
| Xerces-C 3.3.0 | [apache/xerces-c](https://github.com/apache/xerces-c) | `v3.3.0` | `biogears/lib` |
| Eigen 3.4.0 | [libeigen/eigen](https://gitlab.com/libeigen/eigen) | `3.4.0` | compiled into BioGears |

## Quick start

macOS arm64, from a fresh clone, with CMake, Ninja, uv 0.11.28, Rust (rustup) and CodeSynthesis
XSD (`brew install xsd`) installed:

```sh
git submodule update --init --depth 1
cmake --preset macos-arm64-release
cmake --build --preset macos-arm64-release       # writes the bundle to install/macos-arm64-release
ctest --preset macos-arm64-release               # checks the bundle
cmake --build --preset macos-arm64-release --target package
```

The last command writes
`build/macos-arm64-release/package/praenora-runtime-pyenv-<version>-macos-arm64-cp312-<compiler>-release.tar.xz`
and its `.sha256` file. On Linux and Windows, use the `linux-x64-release` and `windows-x64-release`
presets. `-DPRAENORA_PYENV_ENGINES=...` selects the engines
([docs/building.md](docs/building.md#options)).

## Status

Verified on macOS arm64 with AppleClang 17 and CPython 3.12.16: the build with the default engines
(tellurium, copasi, biogears, rust), all checks of `ctest` (among them a simulation with each
engine, a program that embeds the interpreter, and the bundle moved to another directory), and the
archive. The Linux and Windows presets are written but not yet verified. The GitHub Actions
workflow is written but has not run (not yet verified), and no release has been published. The
Praenora runtime does not consume the bundles yet.

## Documentation

- [docs/building.md](docs/building.md): requirements, presets, options, what the build does,
  checking a bundle and updating an upstream.
- [docs/outputs.md](docs/outputs.md): the bundle's layout, name, version scheme, manifest and
  CMake package, how a consumer embeds or runs it, and the licenses of what it holds.
- [docs/upstreams.md](docs/upstreams.md): the upstreams, their pins, the checks that guard against
  their changes, and the drift report.
- [docs/releasing.md](docs/releasing.md): the GitHub Actions workflow, its runners and the release
  procedure.
- [AGENTS.md](AGENTS.md): guide for contributors and coding agents.

## License

This repository's files are under the MIT license ([LICENSE](LICENSE)), copyright The Praenora
developers. The software that the build puts into a bundle is not: each part keeps the license of
its upstream project, and each bundle holds the license files in `licenses/`
([docs/outputs.md](docs/outputs.md#licenses)).
