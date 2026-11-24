"""Reports how the upstreams that follow a branch have moved since their pins.

For each upstream of cmake/PraenoraPyenvVersions.cmake with a branch (PRAENORA_PYENV_<UP>_BRANCH),
compares the branch's head with the pinned commit, and lists the new commits and, where the
upstream has them, the changes of its pyproject.toml (dependencies, extras, [tool.uv.sources])
and of the engines that viva_simulation_core/engines.py names. It builds nothing and changes no
pin (docs/upstreams.md#the-drift-report).

    python tools/upstream_drift.py [--pins FILE] [--summary FILE]

--summary appends the report to FILE as well (GitHub Actions passes $GITHUB_STEP_SUMMARY). Exit
status: 0 when no upstream moved, 1 when one did, 2 when an upstream could not be read.
Python 3.11 or newer, standard library only, and git.
"""

import argparse
import ast
import pathlib
import re
import subprocess
import sys
import tempfile
import tomllib

ROOT = pathlib.Path(__file__).resolve().parents[1]
MAX_COMMITS = 20


class UpstreamError(Exception):
    """An upstream could not be read."""


def read_pins(path):
    """The upstreams with a branch: [(name, repository, commit, branch)]."""
    text = pathlib.Path(path).read_text(encoding="utf-8")
    match = re.search(r"set\(PRAENORA_PYENV_UPSTREAMS\s+([^)]*)\)", text)
    if not match:
        raise UpstreamError(f"{path} sets no PRAENORA_PYENV_UPSTREAMS")
    upstreams = []
    for name in match.group(1).split():
        key = name.upper().replace("-", "_")
        fields = {}
        for field in ("REPOSITORY", "COMMIT", "BRANCH"):
            found = re.search(rf'set\(PRAENORA_PYENV_{key}_{field}\s+"([^"]*)"\)', text)
            fields[field] = found.group(1) if found else ""
        if fields["BRANCH"]:
            upstreams.append((name, fields["REPOSITORY"], fields["COMMIT"], fields["BRANCH"]))
    return upstreams


def git(*arguments, cwd=None):
    result = subprocess.run(["git", *arguments], cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        raise UpstreamError(f"git {' '.join(arguments)}: {result.stderr.strip()}")
    return result.stdout


def show(repository, revision, path):
    """The file `path` at `revision`, or None when it does not exist there."""
    result = subprocess.run(["git", "-C", repository, "show", f"{revision}:{path}"],
                            capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else None


def requirement_name(requirement):
    return re.split(r"[\s\[<>=!~;@(]", requirement.strip(), maxsplit=1)[0].lower()


def compare_lists(label, old, new):
    lines = []
    old_by_name = {requirement_name(item): item for item in old}
    new_by_name = {requirement_name(item): item for item in new}
    for name in sorted(set(old_by_name) | set(new_by_name)):
        before, after = old_by_name.get(name), new_by_name.get(name)
        if before == after:
            continue
        if before is None:
            lines.append(f"  + {after}")
        elif after is None:
            lines.append(f"  - {before}")
        else:
            lines.append(f"  - {before}")
            lines.append(f"  + {after}")
    return [f"- {label}:"] + lines if lines else []


def compare_pyprojects(old_text, new_text):
    """The changes of dependencies, extras and [tool.uv.sources], as Markdown lines."""
    old, new = tomllib.loads(old_text or ""), tomllib.loads(new_text or "")
    lines = []
    lines += compare_lists("dependencies", old.get("project", {}).get("dependencies", []),
                           new.get("project", {}).get("dependencies", []))
    old_extras = old.get("project", {}).get("optional-dependencies", {})
    new_extras = new.get("project", {}).get("optional-dependencies", {})
    for extra in sorted(set(old_extras) | set(new_extras)):
        if extra not in old_extras:
            lines.append(f"- extra added: {extra}")
        elif extra not in new_extras:
            lines.append(f"- extra removed: {extra}")
        lines += compare_lists(f"extra {extra}", old_extras.get(extra, []),
                               new_extras.get(extra, []))
    old_sources = old.get("tool", {}).get("uv", {}).get("sources", {})
    new_sources = new.get("tool", {}).get("uv", {}).get("sources", {})
    for name in sorted(set(old_sources) | set(new_sources)):
        before, after = old_sources.get(name), new_sources.get(name)
        if before != after:
            lines.append(f"- [tool.uv.sources] {name}: {before} -> {after}")
    return lines


def engine_names(text):
    """The keys of _ENGINES in viva_simulation_core/engines.py."""
    if text is None:
        return None
    for node in ast.walk(ast.parse(text)):
        target = getattr(node, "target", None) or (getattr(node, "targets", None) or [None])[0]
        if isinstance(target, ast.Name) and target.id == "_ENGINES" and \
                isinstance(node.value, ast.Dict):
            return [key.value for key in node.value.keys if isinstance(key, ast.Constant)]
    return None


def report_upstream(name, repository, commit, branch, workspace):
    """Markdown lines for one upstream, and whether it moved."""
    heads = git("ls-remote", repository, f"refs/heads/{branch}").split()
    if not heads:
        raise UpstreamError(f"{repository} has no branch {branch}")
    head = heads[0]
    if head == commit:
        return [f"### {name}", f"No drift: {branch} is at the pinned commit {commit}."], False

    clone = str(workspace / name)
    git("clone", "--quiet", "--bare", "--filter=blob:none", "--single-branch", "--branch",
        branch, repository, clone)
    if subprocess.run(["git", "-C", clone, "cat-file", "-e", f"{commit}^{{commit}}"],
                      capture_output=True).returncode != 0:
        git("-C", clone, "fetch", "--quiet", "origin", commit)
    lines = [f"### {name}", f"{branch} moved from the pinned commit {commit} to {head}.", ""]
    log = git("-C", clone, "log", "--format=%h %s", f"{commit}..{head}").splitlines()
    lines.append(f"New commits ({len(log)}):")
    lines += [f"- {entry}" for entry in log[:MAX_COMMITS]]
    if len(log) > MAX_COMMITS:
        lines.append(f"- ... and {len(log) - MAX_COMMITS} more")

    old_pyproject = show(clone, commit, "pyproject.toml")
    new_pyproject = show(clone, head, "pyproject.toml")
    if old_pyproject is not None or new_pyproject is not None:
        changes = compare_pyprojects(old_pyproject, new_pyproject)
        lines += ["", "Changes of pyproject.toml:"] + (changes or ["- none"])

    old_engines = engine_names(show(clone, commit, "viva_simulation_core/engines.py"))
    new_engines = engine_names(show(clone, head, "viva_simulation_core/engines.py"))
    if old_engines is not None or new_engines is not None:
        old_engines, new_engines = old_engines or [], new_engines or []
        changes = [f"- engine added: {engine}" for engine in new_engines
                   if engine not in old_engines]
        changes += [f"- engine removed: {engine}" for engine in old_engines
                    if engine not in new_engines]
        lines += ["", "Changes of the engines:"] + (changes or ["- none"])
    return lines, True


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Reports how the upstreams that follow a branch have moved since their pins.")
    parser.add_argument("--pins", default=str(ROOT / "cmake" / "PraenoraPyenvVersions.cmake"))
    parser.add_argument("--summary")
    arguments = parser.parse_args(argv)

    lines = ["## Upstream drift", ""]
    status = 0
    try:
        upstreams = read_pins(arguments.pins)
    except (OSError, UpstreamError) as error:
        print(f"upstream_drift: {error}", file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory(prefix="praenora-pyenv-drift-") as workspace:
        for name, repository, commit, branch in upstreams:
            try:
                upstream_lines, moved = report_upstream(name, repository, commit, branch,
                                                        pathlib.Path(workspace))
            except UpstreamError as error:
                upstream_lines, moved = [f"### {name}", f"Error: {error}"], False
                status = 2
            lines += upstream_lines + [""]
            if moved and status == 0:
                status = 1
    if status == 0:
        lines.append("Result: no drift.")
    elif status == 1:
        lines.append("Result: upstreams moved; update the pins as docs/building.md says, or "
                     "leave them.")
    else:
        lines.append("Result: an upstream could not be read.")
    text = "\n".join(lines) + "\n"
    print(text, end="")
    if arguments.summary:
        with open(arguments.summary, "a", encoding="utf-8") as summary:
            summary.write(text)
    return status


if __name__ == "__main__":
    sys.exit(main())
