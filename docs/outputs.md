# Outputs

A build produces a bundle: a directory that holds a relocatable CPython 3.12 with the simulation
capability of inflect-sim-core and its engines installed, what the engines need at run time, the
license files, a manifest and a CMake package. The `package` target archives it, and releases of
this repository publish the archives ([releasing.md](releasing.md)). This document describes the
bundle, its name and version, how the
[Praenora runtime](https://github.com/INFLECT-Praenora/praenora-runtime) can consume it, and the
licenses of what it holds.

## Layout

```
<bundle>/
  praenora-runtime-pyenv.json     manifest
  lib/cmake/PraenoraRuntimePyenv/ CMake package: version and platform check, variables
  python/                         CPython 3.12 (python-build-standalone): bin/python3.12,
                                  lib/libpython3.12.dylib (.so.1.0 on Linux; python312.dll and
                                  libs/python312.lib on Windows), include/python3.12/, the
                                  standard library and lib/python3.12/site-packages/ with the
                                  installed distributions
  biogears/                       with the biogears engine only: lib/ (BioGears' and Xerces-C's
                                  shared libraries) and share/biogears/runtime/ (BioGears' data,
                                  the directory that BIOGEARS_RUNTIME names)
  licenses/                       license files ([Licenses](#licenses))
```

The verified macOS arm64 bundle with the default engines holds 120 distributions and takes 1.1 GB;
its archive takes 197 MB.

## Names

A bundle's name identifies its version, platform, Python ABI, compiler and build type:

```
praenora-runtime-pyenv-<version>-<os>-<arch>-<python>-<compiler>-<config>
```

for example `praenora-runtime-pyenv-0.1.0-macos-arm64-cp312-appleclang17-release`. No field
contains `-`.

| Field | Values | Source |
|---|---|---|
| `version` | `MAJOR.MINOR.PATCH` ([Versions](#versions)) | `project(VERSION)` in `CMakeLists.txt` |
| `os` | `linux`, `macos`, `windows` | the target system |
| `arch` | `x86_64`, `arm64` | `CMAKE_OSX_ARCHITECTURES` on macOS, the compiler's target elsewhere |
| `python` | `cp312` | the CPython ABI tag of the interpreter and of every extension module |
| `compiler` | `appleclang<major>`, `clang<major>`, `gcc<major>`, `msvc<toolset>` | the C++ compiler that built BioGears, Xerces-C and the extension modules built from source |
| `config` | `release` | bundles are Release builds only |

The operating system and architecture names are the Praenora runtime's. The engines are not in the
name: published bundles hold the default engines of their platform, and the manifest and the CMake
package name them. The archive is `<name>.tar.xz` on Linux and macOS and `<name>.zip` on Windows,
in `build/<preset>/package/`; it unpacks into `<name>/`, and `<name>.tar.xz.sha256` (or
`.zip.sha256`) beside it holds its SHA-256 in the format of `sha256sum`.

## Versions

The bundle's version follows semantic versioning and is independent of the upstream versions,
which the manifest records. It is `project(VERSION)` in `CMakeLists.txt`, repeated in
`pyproject.toml`.

- **Minor version** (while the major version is 0), or **major version** (from 1.0): raised by
  every change to what a consumer gets: a submodule commit, a change of `uv.lock`, the CPython
  archive, the default engines, a build option, the compiler of a runner image, the layout, or the
  manifest format.
- **Patch version**: raised by changes that leave the environment as it was, such as a new
  manifest member, a change of the license files, a fix to the CMake package or the checks, or
  documentation.

A published release is never replaced, so a bundle that must be built again gets a new version.
The CMake package accepts a requested version when the bundle's version is at least that version
and, while the major version is 0, has the same minor version. A consumer requests `MAJOR.MINOR`,
for example `find_package(PraenoraRuntimePyenv 0.1)`.

## Manifest

`praenora-runtime-pyenv.json` is one JSON object. Paths are relative to the bundle directory. A
value that could not be determined is `null`. Object members are in alphabetical order.

| Member | Meaning |
|---|---|
| `manifest_version` | Format version of the manifest, `1`. Raised when a member is removed or changes meaning. |
| `name`, `version`, `package` | `praenora-runtime-pyenv`, the bundle's version and its name. |
| `source` | This repository (`repository`), the commit built (`commit`), whether tracked files had uncommitted changes (`modified`), and its license file (`licenses`). |
| `platform` | `os`, `arch`; `os_min_version`: on macOS, the highest minimum macOS version of any binary of the bundle but those that `PRAENORA_PYENV_OS_MIN_VERSION_IGNORE` names (14.0 for the verified bundle); `distribution`: on Linux, such as `ubuntu-24.04`. |
| `compiler` | `id`, `version`, `label`, `cxx_stdlib` and, on Windows, `msvc_runtime`. |
| `build_type` | `Release`. |
| `python` | `version`, `abi`, `implementation`, the python-build-standalone `release`, `archive` and `sha256`, and the paths `home`, `executable`, `library`, `include_dir`, `site_packages`; `licenses`: CPython's license file. |
| `tools` | The versions of `uv`, `rust` and `xsd` that built the bundle (`null` when not used). |
| `lock` | `sha256`: the SHA-256 of the `uv.lock` the bundle was installed from. |
| `upstreams.<name>` | For each upstream the bundle holds: `repository`, `ref`, `commit`, `modified`, `version` and `licenses`. |
| `engines.<name>` | For each engine: its wrapper `distribution` and `version`; for `biogears`, `runtime_dir`. |
| `distributions` | Every installed distribution: `name`, `version`, `source` (`registry`, `git+<url>@<commit>` or `local`), `license` (from its metadata) and `license_files`. |
| `excluded` | The distributions that the bundle must not hold. |
| `environment` | `paths`: environment variables whose values are paths relative to the bundle (`PYTHONHOME`, and `BIOGEARS_RUNTIME` with BioGears); `values`: variables with literal values (`PYTHONNOUSERSITE`, `PYTHONDONTWRITEBYTECODE`, an empty `PYTHONPATH` and `PYTHONSAFEPATH`, so that a caller's `PYTHONPATH` and current directory cannot shadow the bundle's modules). |
| `consumer` | `python_root_dir`, the directory for CMake's `Python3_ROOT_DIR`, and `cmake_package_dir`. |

## CMake package

`lib/cmake/PraenoraRuntimePyenv` holds a package that defines variables and no targets. It is found
with the bundle directory on `CMAKE_PREFIX_PATH`, or with `PraenoraRuntimePyenv_DIR` set to that
directory. Its engines are components:
`find_package(PraenoraRuntimePyenv 0.1 CONFIG REQUIRED COMPONENTS biogears tellurium)` stops when
the bundle lacks one of them.

`PraenoraRuntimePyenvConfigVersion.cmake` checks the request ([Versions](#versions)) and refuses the
bundle, whatever the requested version, when the consuming project targets another operating
system or architecture, a macOS deployment target older than `platform.os_min_version`, or, with
MSVC, an older toolset than the one that built the bundle.

| Variable (prefix `PraenoraRuntimePyenv_`) | Value |
|---|---|
| `ROOT`, `MANIFEST`, `PACKAGE_NAME` | The bundle directory, the manifest's path and the bundle's name. |
| `OS`, `ARCH`, `OS_MIN_VERSION`, `COMPILER_ID`, `COMPILER_VERSION`, `COMPILER_LABEL`, `CXX_STDLIB`, `MSVC_RUNTIME`, `BUILD_TYPE` | The labels, as in the manifest. |
| `PYTHON_VERSION`, `PYTHON_ABI` | `3.12.16`, `cp312`. |
| `PYTHON_HOME`, `PYTHON_EXECUTABLE`, `PYTHON_INCLUDE_DIR`, `PYTHON_LIBRARY`, `PYTHON_SITE_PACKAGES` | Absolute paths in the bundle. |
| `ENGINES` | The bundle's engines. |
| `BIOGEARS_RUNTIME` | BioGears' data directory, or empty. |
| `ENVIRONMENT` | The environment of a process that runs the bundle's Python, as `NAME=value` with absolute paths. |

## Consuming a bundle

The Praenora runtime cannot run Python modules or service providers yet; this section describes
how a consumer uses a bundle. Not yet verified in the runtime.

### Embedding

A program that embeds the interpreter finds the package, then CPython's development files in the
bundle, and links libpython:

```cmake
find_package(PraenoraRuntimePyenv 0.1 CONFIG REQUIRED COMPONENTS tellurium)
set(Python3_ROOT_DIR "${PraenoraRuntimePyenv_PYTHON_HOME}")
set(Python3_FIND_STRATEGY LOCATION)
set(Python3_FIND_REGISTRY NEVER)
set(Python3_FIND_FRAMEWORK NEVER)
find_package(Python3 3.12.16 EXACT REQUIRED COMPONENTS Development.Embed)
target_link_libraries(<target> PRIVATE Python3::Python)
```

At run time, it initializes an isolated interpreter (`PyConfig_InitIsolatedConfig`) with `home`
set to `PraenoraRuntimePyenv_PYTHON_HOME`, `executable` set to
`PraenoraRuntimePyenv_PYTHON_EXECUTABLE`, and `write_bytecode` set to 0, so that it writes nothing
into the bundle (an isolated configuration ignores `PYTHONDONTWRITEBYTECODE`): an embedded CPython
otherwise derives its prefix from the host program, and packages that start Python subprocesses
use `sys.executable`. Before it sets the paths, it preinitializes the interpreter in UTF-8 mode
(`PyPreConfig_InitIsolatedConfig`, `utf8_mode` set to 1, `Py_PreInitialize`): an isolated
configuration does not set the locale, and in the C locale an interpreter on Linux decodes and
encodes file names as ASCII, which fails for a bundle under a path with other characters. With
BioGears, it sets `BIOGEARS_RUNTIME`. On Windows, `python312.dll` must be on the DLL search path,
and `PyConfig_SetBytesString` decodes the paths as UTF-8: a program built with MSVC that holds them
in string literals is compiled with `/utf-8`. The paths of a bundle's deepest files exceed 260
characters when the bundle lies in a deep directory; Windows opens them only for a program whose
manifest declares it long-path-aware (`longPathAware`, as in `python.exe`'s manifest), with long
paths enabled in Windows (`LongPathsEnabled`) (not yet verified). The test `bundle.embed` builds
and runs such a program ([tests/embed](../tests/embed/embed.cpp)), and `bundle.relocated` runs it
against a copy of the bundle under a path with a space and a non-ASCII character.

### A separate process

A consumer runs `PraenoraRuntimePyenv_PYTHON_EXECUTABLE` with the variables of
`PraenoraRuntimePyenv_ENVIRONMENT` (the manifest's `environment`), or with `-I` (isolated mode)
and `-B`. Console scripts in
`python/bin` find the interpreter beside them; prefer `python -m <module>`.

### Notes for consumers

- The Praenora runtime's own Python extension (`praenora.runtime`) is built for one interpreter;
  configured with `-DPython3_EXECUTABLE=<bundle>/python/bin/python3.12`, it is built for the
  bundle's (not yet verified).
- tellurium's `libroadrunner` wheel holds its own libRoadRunner and LLVM. A process that also
  loads the runtime's `roadrunner` service provider holds two copies of them; run Python steps in
  a module host (not yet verified).
- inflect-sim-core's `build_core()` reads a `workspace.yaml` in the current directory, or in the
  directory that `WORKSPACE_DIR` names, when one exists, and imports the packages it lists; run
  consumers from a directory without one, with `WORKSPACE_DIR` unset.
- BioGears' libraries hold the path of their installation in the build tree as a string. The
  bundle's checks set `BIOGEARS_RUNTIME`, which names the data directory in the bundle.

### From a release

The release `v<version>` of this repository holds the archive of each bundle of that version and
its `.sha256` file ([releasing.md](releasing.md)), at
`https://github.com/INFLECT-Praenora/praenora-runtime-pyenv/releases/download/v<version>/<file>`.
Published releases do not change. A consumer pins the version and, for each platform, the
archive's name and SHA-256, and checks the archive against the pinned SHA-256 after downloading
it, as the Praenora runtime does for the bundles of
[praenora-runtime-deps](https://github.com/INFLECT-Praenora/praenora-runtime-deps)
(`cmake/PraenoraRuntimeDepsPin.cmake` and `cmake/praenora_fetch_runtime_deps.cmake` in the
runtime's repository). A consumer builds with the compiler that built the bundle, or a newer one of
the same family.

## Licenses

This repository's files are under the MIT license ([LICENSE](../LICENSE)): the build, the checks,
the documentation, and the manifest and CMake package that the build writes into a bundle. What a
bundle holds is not: each part keeps the license of its upstream project. The bundle step copies
into `licenses/`:

- `praenora-runtime-pyenv/LICENSE`, this repository's license;
- `python/LICENSE.txt`, CPython's license, as python-build-standalone ships it;
- `<upstream>/<path>`, the license files of each upstream that `cmake/PraenoraPyenvVersions.cmake`
  lists (`PRAENORA_PYENV_<UP>_LICENSES`);
- `python-packages/<distribution>/<path>`, the license files in each installed distribution's
  `.dist-info` directory.

The build stops when an upstream's license file is missing, or when a distribution ships none and
is not on `PRAENORA_PYENV_LICENSE_ALLOWLIST` with its license as checked. The manifest lists every
file (`source.licenses`, `python.licenses`, `upstreams.<name>.licenses`,
`distributions[].license_files`).

| Part | License, as its files or metadata state it |
|---|---|
| CPython | PSF License |
| inflect-sim-core (`simulation-core`) | Apache License 2.0 |
| BioGears 8.2.0, with its bundled minizip and zlib | Apache License 2.0; zlib license |
| pybiogears | Apache License 2.0 |
| Xerces-C 3.3.0 | Apache License 2.0 |
| Eigen 3.4.0 (compiled into BioGears) | MPL 2.0; some files under the licenses that `COPYING.README` names |
| CodeSynthesis XSD's generated code and `libxsd` headers (compiled into BioGears) | GPL 2.0 with the FLOSS License Exception |
| python-copasi | Artistic License (its metadata) |
| libroadrunner (tellurium) | Apache License 2.0; its `NOTICE.txt` names the NLEQ1 and NLEQ2 solvers of the Zuse Institute Berlin |
| antimony (wheel) | BSD 3-Clause (libAntimony's LICENSE.txt; the wheel's metadata says MIT; on the allow-list) |
| phrasedml (wheel, Linux and Windows) | BSD 3-Clause (phrasedml's LICENSE.txt at tag 1.3.0; the wheel's metadata says MIT; on the allow-list) |
| Other distributions | As their files in `licenses/python-packages/` state |

The table summarizes what the files say; no license review has been made. Points that publishing
bundles depends on:

- **NLEQ1 and NLEQ2**, which libroadrunner's `NOTICE.txt` names: their terms allow
  non-commercial use and require ZIB's permission for delivery, as praenora-runtime-deps'
  documentation describes for its bundles. Whether bundles that hold them may be published is
  open.
- **CodeSynthesis XSD**: BioGears compiles XSD-generated code and the `libxsd` headers; their GPL
  2.0 terms carry an exception for FLOSS software such as BioGears.
- **The other distributions** are installed from PyPI and git under the licenses their metadata
  states; the manifest records each.
