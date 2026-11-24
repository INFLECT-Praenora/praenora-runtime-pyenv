# Releasing

This document describes how GitHub Actions builds the bundles, how an administrator publishes them
as a release that automated builds of the
[Praenora runtime](https://github.com/INFLECT-Praenora/praenora-runtime) can download, and the
scheduled drift report. What a bundle holds and how it is consumed is in [outputs.md](outputs.md);
building one on your own machine is in [building.md](building.md).

Not yet verified: the workflow has not run on GitHub, and its Linux and Windows builds are the first
builds of those presets.

## The workflow

[`.github/workflows/build.yml`](../.github/workflows/build.yml) (named "Build") runs:

- on every pull request to `main`;
- when run manually, on any branch: in the repository's Actions tab, *Build*, *Run workflow*; or
  `gh workflow run build.yml --ref <branch>`. With the input `publish`, which only `main` accepts,
  the run also creates a draft release;
- every Monday on `main`, for the job *Drift* only.

Its jobs:

1. **Prepare** reads the bundle's version from `project(VERSION)` in `CMakeLists.txt`. With
   `publish`, it stops the run unless the run is on `main` and the tag `v<version>` does not exist.
2. **One build job per preset**:

   | Job | Runner | Compiler (expected) | Engines | Archive |
   |---|---|---|---|---|
   | `linux-x64-release` | `ubuntu-24.04` | GCC 13 | tellurium, copasi, biogears, rust | `praenora-runtime-pyenv-<version>-linux-x86_64-cp312-gcc13-release.tar.xz` |
   | `macos-arm64-release` | `macos-26` | AppleClang (Xcode of the image) | tellurium, copasi, biogears, rust | `praenora-runtime-pyenv-<version>-macos-arm64-cp312-appleclang<major>-release.tar.xz` |
   | `windows-x64-release` | `windows-2022` | MSVC of Visual Studio 2022 (toolset 143) | tellurium, copasi, rust | `praenora-runtime-pyenv-<version>-windows-x86_64-cp312-msvc143-release.zip` |

   Each job checks out the repository, fetches the submodules with
   `git submodule update --init --depth 1`, installs uv 0.11.28 (`astral-sh/setup-uv`), Rust
   1.100.0 (rustup), and Ninja, CodeSynthesis XSD and patchelf (Linux) or Ninja and XSD (macOS),
   or enters the Visual Studio 2022 developer environment (Windows). It runs the commands of
   [building.md](building.md#presets): configure, build, `ctest`, and the `package` target. It
   checks that the manifest records unmodified sources (`source.modified` and every
   `upstreams.<name>.modified` are `false`) and uploads the archive and its `.sha256` file as a
   workflow artifact named after the preset, kept for 7 days.
3. **Draft release**, with `publish` only: downloads the archives, checks that their names carry
   the version and that they match their `.sha256` files, writes release notes with the upstreams
   and engines from the Linux bundle's manifest, and creates the draft release `v<version>` of the
   built commit, with every archive and `.sha256` file. Publishing the draft creates the tag.
4. **Drift**, on the schedule only: runs `tools/upstream_drift.py`
   ([upstreams.md](upstreams.md#the-drift-report)) and writes its report to the run's summary. The
   job fails when an upstream moved, which notifies the maintainers; it builds nothing.

The runner labels name fixed image versions, never `-latest`: the compiler of the image names the
bundle, and a consumer builds with that compiler or a newer one of the same family. Actions are
pinned to commits.

**Required checks.** The jobs report `Prepare`, `linux-x64-release`, `macos-arm64-release` and
`windows-x64-release`; the ruleset on `main` can require them. *Drift* runs only on the schedule
and is not a required check.

## Repository settings

The release procedure relies on the settings that praenora-runtime-deps uses: `main` takes changes
only through pull requests with the checks above; tags `v*` are created by administrators only;
immutable releases are on; the default `GITHUB_TOKEN` reads contents only, and the release job asks
for `contents: write` itself; if the allowed actions are restricted, `actions/checkout`,
`actions/upload-artifact`, `actions/download-artifact` and `astral-sh/setup-uv` are allowed.

## Release procedure

1. **Prepare the change.** In a pull request to `main`, raise `project(VERSION)` in
   `CMakeLists.txt` and `version` in `pyproject.toml` as [outputs.md](outputs.md#versions) says,
   with the change it versions. The pull request's checks build and check every bundle.
2. **Merge** the pull request into `main`.
3. **Run the workflow with `publish`** on `main`:

   ```sh
   gh workflow run build.yml --ref main -f publish=true
   ```

   The run stops at once if the tag `v<version>` exists; then the version was not raised.
4. **Check the draft release** `v<version>` when the run has finished. It holds three archives and
   three `.sha256` files. The archive names carry the version and the expected compiler labels.
   Download the archive of your platform, check it with `shasum -a 256 -c`, unpack it and run its
   Python checks ([building.md](building.md#checking-a-bundle)). Check that the bundles may be
   published under the licenses of what they hold ([outputs.md](outputs.md#licenses)).
5. **Publish** the release. It then cannot change.
6. **Update the consumers**: a pull request of the Praenora runtime, once it consumes these bundles,
   raises its pin to the new version and the archives' SHA-256 values
   ([outputs.md](outputs.md#from-a-release)).

If a build job fails, the run creates no release. A draft that should not be published is deleted
with `gh release delete v<version> --repo INFLECT-Praenora/praenora-runtime-pyenv`; the workflow can
then run again for the same version.

## Changing a runner image

When a job moves to another runner label, or an image changes its compiler's major version, the
compiler label in that bundle's name changes. Then, in one pull request: change the label in the
workflow, raise the bundle's minor version, and update the table in [The workflow](#the-workflow)
and the status in [building.md](building.md#presets).
