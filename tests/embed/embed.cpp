// A program that embeds the bundle's CPython, as a process of the Praenora runtime would: an
// isolated interpreter whose home and executable are the bundle's, which imports inflect-sim-core
// and runs one simulation with the engine given as the first argument (tellurium, copasi, or
// none for the import only). Exit status 0 on success.

#include <Python.h>

#include <cstdio>
#include <string>

#ifndef PRAENORA_PYENV_PYTHON_HOME
#error "PRAENORA_PYENV_PYTHON_HOME is not defined"
#endif
#ifndef PRAENORA_PYENV_PYTHON_EXECUTABLE
#error "PRAENORA_PYENV_PYTHON_EXECUTABLE is not defined"
#endif

namespace {

bool initialize() {
    // UTF-8 mode: the interpreter decodes the paths below and encodes file names as UTF-8. An
    // isolated configuration does not set the locale, and in the C locale an interpreter on Linux
    // uses ASCII. The preinitialization comes first: PyConfig_SetBytesString decodes with it.
    PyPreConfig preconfig;
    PyPreConfig_InitIsolatedConfig(&preconfig);
    preconfig.utf8_mode = 1;
    PyStatus status = Py_PreInitialize(&preconfig);
    PyConfig config;
    PyConfig_InitIsolatedConfig(&config);
    // An isolated configuration ignores PYTHONDONTWRITEBYTECODE; nothing is written into the bundle.
    config.write_bytecode = 0;
    if (!PyStatus_Exception(status)) {
        status = PyConfig_SetBytesString(&config, &config.home, PRAENORA_PYENV_PYTHON_HOME);
    }
    if (!PyStatus_Exception(status)) {
        status = PyConfig_SetBytesString(&config, &config.executable,
                                         PRAENORA_PYENV_PYTHON_EXECUTABLE);
    }
    if (!PyStatus_Exception(status)) {
        status = Py_InitializeFromConfig(&config);
    }
    PyConfig_Clear(&config);
    if (PyStatus_Exception(status)) {
        std::fprintf(stderr, "embed: initialization failed: %s\n",
                     status.err_msg != nullptr ? status.err_msg : "(no message)");
        return false;
    }
    return true;
}

}  // namespace

int main(int argc, char** argv) {
    const std::string engine = argc > 1 ? argv[1] : "none";
    if (!initialize()) {
        return 1;
    }
    // The same model as tests/python/support.py: A(t) = 10 exp(-0.5 t).
    const std::string code =
        "import math, pathlib, sys\n"
        "home = pathlib.Path(r'''" PRAENORA_PYENV_PYTHON_HOME "''').resolve()\n"
        "prefix = pathlib.Path(sys.prefix).resolve()\n"
        "assert prefix == home, f'sys.prefix is {prefix}, not {home}'\n"
        "import viva_simulation_core as v\n"
        "module = pathlib.Path(v.__file__).resolve()\n"
        "assert module.is_relative_to(home), f'viva_simulation_core is {module}'\n"
        "engine = '" + engine + "'\n"
        "if engine != 'none':\n"
        "    model = \"model m\\n  A' = -k*A\\n  A = 10; k = 0.5\\nend\"\n"
        "    out = v.simulate(model, duration=4, interval=1, observables=['A'], engine=engine,\n"
        "                     model_format='antimony')\n"
        "    value = out.results['A'][4]\n"
        "    assert abs(value / (10 * math.exp(-2)) - 1) < 1e-5, value\n"
        "print('embed: ok', engine, sys.version.split()[0])\n";
    const int result = PyRun_SimpleString(code.c_str());
    if (Py_FinalizeEx() < 0) {
        std::fprintf(stderr, "embed: finalization failed\n");
        return 1;
    }
    return result == 0 ? 0 : 1;
}
