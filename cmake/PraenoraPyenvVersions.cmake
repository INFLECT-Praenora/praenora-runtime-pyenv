# What the bundle is built from: the CPython archives, the tools, the upstream submodules, the
# distributions the bundle must not hold, and the format version of the manifest. A change here
# changes the bundle; raise the version in CMakeLists.txt with it (docs/outputs.md#versions).
#
# Defines:
#   PRAENORA_PYENV_MANIFEST_VERSION       format version of praenora-runtime-pyenv.json
#   PRAENORA_PYENV_PYTHON_VERSION, _ABI   the CPython version and its ABI tag
#   PRAENORA_PYENV_PYTHON_RELEASE         the python-build-standalone release
#   PRAENORA_PYENV_PYTHON_BASE_URL        where its archives are
#   PRAENORA_PYENV_PYTHON_<OS>_<ARCH>_ARCHIVE, _SHA256
#                                         the archive of each platform and its SHA-256, with
#                                         <OS>_<ARCH> one of MACOS_ARM64, LINUX_X86_64,
#                                         WINDOWS_X86_64
#   PRAENORA_PYENV_UV_VERSION             the uv version that locks and installs
#   PRAENORA_PYENV_RUST_MIN_VERSION       the oldest Rust that builds the rust engine
#   PRAENORA_PYENV_UPSTREAMS              the submodules, by name
#   PRAENORA_PYENV_<UP>_REPOSITORY, _REF, _COMMIT, _BRANCH, _PATH, _LICENSES
#                                         for each upstream, <UP> being its name in upper case with
#                                         '-' as '_': its repository, the tag or commit it is
#                                         pinned at, the commit, the branch the drift report
#                                         follows (empty for a release tag), its path below the
#                                         source directory and its license files (paths in it)
#   PRAENORA_PYENV_VIVA_SOURCES           name=revision of the git sources this repository's
#                                         pyproject.toml pins as inflect-sim-core's does
#   PRAENORA_PYENV_EXCLUDED_DISTRIBUTIONS distributions the bundle must not hold
#   PRAENORA_PYENV_EXPECTED_VERSIONS      name=version of the installed distributions the bundle
#                                         step checks
#   PRAENORA_PYENV_LICENSE_ALLOWLIST      name=license of installed distributions that ship no
#                                         license file

include_guard(GLOBAL)

set(PRAENORA_PYENV_MANIFEST_VERSION 1)

# CPython: python-build-standalone's install_only archives (unstripped), with the SHA-256 values of
# the release's SHA256SUMS file.
set(PRAENORA_PYENV_PYTHON_VERSION "3.12.16")
set(PRAENORA_PYENV_PYTHON_ABI "cp312")
set(PRAENORA_PYENV_PYTHON_RELEASE "20261123")
set(PRAENORA_PYENV_PYTHON_BASE_URL
    "https://github.com/astral-sh/python-build-standalone/releases/download/20261123")
set(_praenora_pyenv_python "cpython-3.12.16+20261123")
set(PRAENORA_PYENV_PYTHON_MACOS_ARM64_ARCHIVE
    "${_praenora_pyenv_python}-aarch64-apple-darwin-install_only.tar.gz")
set(PRAENORA_PYENV_PYTHON_MACOS_ARM64_SHA256
    "4068a8a2355083e29f84138c1c6ce70654e5833424bbe79e63289031a11fd8b2")
set(PRAENORA_PYENV_PYTHON_LINUX_X86_64_ARCHIVE
    "${_praenora_pyenv_python}-x86_64-unknown-linux-gnu-install_only.tar.gz")
set(PRAENORA_PYENV_PYTHON_LINUX_X86_64_SHA256
    "386028a53cceb3be3c1ef8d8828f707d7d3aab67631049f9806e0fb3665a40c8")
set(PRAENORA_PYENV_PYTHON_WINDOWS_X86_64_ARCHIVE
    "${_praenora_pyenv_python}-x86_64-pc-windows-msvc-install_only.tar.gz")
set(PRAENORA_PYENV_PYTHON_WINDOWS_X86_64_SHA256
    "93584a7bee14bf6b91a03efdbb128419147279a64934fbc95934c9f53e1191e5")

set(PRAENORA_PYENV_UV_VERSION "0.11.28")

# The oldest Rust that builds viva-core: the rust-version of PyO3 0.29, which viva-core uses.
set(PRAENORA_PYENV_RUST_MIN_VERSION "1.83")

# Upstream submodules (docs/upstreams.md).
set(PRAENORA_PYENV_UPSTREAMS inflect-sim-core biogears pybiogears xerces-c eigen)

set(PRAENORA_PYENV_INFLECT_SIM_CORE_REPOSITORY
    "https://github.com/INFLECT-Praenora/inflect-sim-core")
set(PRAENORA_PYENV_INFLECT_SIM_CORE_REF "9a10a27dd8b12f15ea2ccdd0bba2ba4ecdd77665")
set(PRAENORA_PYENV_INFLECT_SIM_CORE_COMMIT "9a10a27dd8b12f15ea2ccdd0bba2ba4ecdd77665")
set(PRAENORA_PYENV_INFLECT_SIM_CORE_BRANCH "main")
set(PRAENORA_PYENV_INFLECT_SIM_CORE_PATH "external/inflect-sim-core")
set(PRAENORA_PYENV_INFLECT_SIM_CORE_LICENSES "LICENSE")

set(PRAENORA_PYENV_BIOGEARS_REPOSITORY "https://github.com/BioGearsEngine/core")
set(PRAENORA_PYENV_BIOGEARS_REF "8.2.0")
set(PRAENORA_PYENV_BIOGEARS_COMMIT "c5227b63888a7b600087f6aeff7c5649d9b7e8f9")
set(PRAENORA_PYENV_BIOGEARS_BRANCH "")
set(PRAENORA_PYENV_BIOGEARS_PATH "external/biogears")
set(PRAENORA_PYENV_BIOGEARS_LICENSES "LICENSE.txt")

set(PRAENORA_PYENV_PYBIOGEARS_REPOSITORY "https://github.com/vivarium-collective/pybiogears")
set(PRAENORA_PYENV_PYBIOGEARS_REF "01db2efc3db1aaae5a01cf8f1ccef725c60d0c30")
set(PRAENORA_PYENV_PYBIOGEARS_COMMIT "01db2efc3db1aaae5a01cf8f1ccef725c60d0c30")
set(PRAENORA_PYENV_PYBIOGEARS_BRANCH "main")
set(PRAENORA_PYENV_PYBIOGEARS_PATH "external/pybiogears")
set(PRAENORA_PYENV_PYBIOGEARS_LICENSES "LICENSE")

set(PRAENORA_PYENV_XERCES_C_REPOSITORY "https://github.com/apache/xerces-c")
set(PRAENORA_PYENV_XERCES_C_REF "v3.3.0")
set(PRAENORA_PYENV_XERCES_C_COMMIT "31b4b3a06105dcd607db9fda9d1883ad7e489bfe")
set(PRAENORA_PYENV_XERCES_C_BRANCH "")
set(PRAENORA_PYENV_XERCES_C_PATH "external/xerces-c")
set(PRAENORA_PYENV_XERCES_C_LICENSES "LICENSE;NOTICE")

set(PRAENORA_PYENV_EIGEN_REPOSITORY "https://gitlab.com/libeigen/eigen")
set(PRAENORA_PYENV_EIGEN_REF "3.4.0")
set(PRAENORA_PYENV_EIGEN_COMMIT "3147391d946bb4b6c68edd901f2add6ac1f31f8c")
set(PRAENORA_PYENV_EIGEN_BRANCH "")
set(PRAENORA_PYENV_EIGEN_PATH "external/eigen")
# Eigen is MPL 2.0; some of its files are under the other licenses that COPYING.README names.
set(PRAENORA_PYENV_EIGEN_LICENSES COPYING.README COPYING.MPL2 COPYING.APACHE COPYING.BSD
    COPYING.GPL COPYING.LGPL COPYING.MINPACK)

# The git sources that inflect-sim-core pins in its own [tool.uv.sources] and that this
# repository's pyproject.toml names too; configuration stops when the two differ.
set(PRAENORA_PYENV_VIVA_SOURCES
    "viva-superpowers=fe4064a65d1da63452af73de49e57cc975f47bb4"
    "viva-workspace=7ad2eb1a43bbb502158a69982c608f5aa66a1de6")

# Distributions that inflect-sim-core requires for its workbench and reports, which
# pyproject.toml removes (docs/upstreams.md#excluded-distributions).
set(PRAENORA_PYENV_EXCLUDED_DISTRIBUTIONS vivarium-workbench bigraph-viz)

# The versions of the distributions that carry the simulation capability and its engines, as the
# lock installs them. A re-lock that changes one changes this list in the same change; the bundle
# step stops when an installed version differs.
set(PRAENORA_PYENV_EXPECTED_VERSIONS
    "simulation-core=0.0.0"
    "process-bigraph=1.11.2"
    "bigraph-schema=1.8.3"
    "viva-tellurium=0.2.3"
    "tellurium=2.2.13.1"
    "libroadrunner=2.11.0"
    "viva-copasi=0.2.2"
    "python-copasi=4.48.311"
    "copasi-basico=0.92"
    "viva-biogears=0.1.0"
    "pybiogears=0.0.1"
    "viva-superpowers=0.30.0"
    "viva-workspace=0.1.0"
    "viva-core=0.1.0")

# Binaries that the macOS measurement of the bundle (platform.os_min_version) leaves out, as
# regular expressions of their paths, each with the reason: none of them is loaded to simulate.
# debugpy (which tellurium's ipykernel requires) ships a helper for attaching its debugger to
# another process that targets macOS 15.0.
set(PRAENORA_PYENV_OS_MIN_VERSION_IGNORE
    "/debugpy/_vendored/pydevd/pydevd_attach_to_process/")

# Installed distributions that ship no license file, with their license as checked
# (docs/outputs.md#licenses).
set(PRAENORA_PYENV_LICENSE_ALLOWLIST
    "antimony=BSD-3-Clause (libAntimony's LICENSE.txt; the wheel's metadata says MIT)")
