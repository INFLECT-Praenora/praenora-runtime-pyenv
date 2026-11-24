# The checks of this repository's configuration logic and of the bundle in CMAKE_INSTALL_PREFIX
# (docs/building.md#checking-a-bundle).

add_test(NAME config.submodules
    COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE_DIR=${PROJECT_SOURCE_DIR}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/check_submodules.cmake")

add_test(NAME config.engines
    COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE_DIR=${PROJECT_SOURCE_DIR}"
        "-DWORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/engines"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/check_engines.cmake")

# The environment of the bundle's checks: the bundle, its engines (separated by ';', escaped for
# the ENVIRONMENT property) and, with BioGears, its data directory.
list(JOIN PRAENORA_PYENV_ENGINES_RESOLVED "\\;" _praenora_pyenv_engines)
set(PRAENORA_PYENV_TEST_ENVIRONMENT
    "PRAENORA_PYENV_BUNDLE=${CMAKE_INSTALL_PREFIX}"
    "PRAENORA_PYENV_ENGINES=${_praenora_pyenv_engines}")
if(biogears IN_LIST PRAENORA_PYENV_ENGINES_RESOLVED)
    list(APPEND PRAENORA_PYENV_TEST_ENVIRONMENT
        "BIOGEARS_RUNTIME=${CMAKE_INSTALL_PREFIX}/${PRAENORA_PYENV_BIOGEARS_RUNTIME_REL}")
endif()

# The Python tests of tests/python, run by the bundle's interpreter in isolated mode (-I), without
# writing bytecode into the bundle or the source tree (-B).
add_test(NAME python.unittest
    COMMAND "${PRAENORA_PYENV_PYTHON_EXECUTABLE}" -I -B -m unittest discover
        -s "${CMAKE_CURRENT_SOURCE_DIR}/python" -t "${CMAKE_CURRENT_SOURCE_DIR}/python" -v
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
set_tests_properties(python.unittest PROPERTIES
    TIMEOUT 1800
    ENVIRONMENT "${PRAENORA_PYENV_TEST_ENVIRONMENT}")

# The manifest and the files of the bundle.
list(JOIN PRAENORA_PYENV_ENGINES_RESOLVED "," _praenora_pyenv_engines_commas)
add_test(NAME bundle.manifest
    COMMAND "${CMAKE_COMMAND}"
        "-DBUNDLE=${CMAKE_INSTALL_PREFIX}"
        "-DPACKAGE_NAME=${PRAENORA_PYENV_PACKAGE_NAME}"
        "-DVERSION=${PROJECT_VERSION}"
        "-DOS=${PRAENORA_PYENV_OS}"
        "-DARCH=${PRAENORA_PYENV_ARCH}"
        "-DCOMPILER_LABEL=${PRAENORA_PYENV_COMPILER_LABEL}"
        "-DENGINES=${_praenora_pyenv_engines_commas}"
        "-DPINS=${PROJECT_SOURCE_DIR}/cmake/PraenoraPyenvVersions.cmake"
        "-DBUILD_DIR=${PROJECT_BINARY_DIR}"
        "-DSOURCE_DIR=${PROJECT_SOURCE_DIR}"
        "-DUV_CACHE_DIR=${PRAENORA_PYENV_UV_CACHE_DIR}"
        "-DBIOGEARS_LIB_REL=${PRAENORA_PYENV_BIOGEARS_LIB_REL}"
        "-DOSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/check_manifest.cmake")

# A program that embeds the bundle's CPython, and the bundle moved to another directory.
set(_praenora_pyenv_consumer_args
    "-DVERSION=${PROJECT_VERSION}"
    "-DGENERATOR=${CMAKE_GENERATOR}"
    "-DCXX_COMPILER=${CMAKE_CXX_COMPILER}"
    "-DENGINES=${_praenora_pyenv_engines_commas}")
if(APPLE)
    list(APPEND _praenora_pyenv_consumer_args
        "-DOSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}")
endif()
add_test(NAME bundle.embed
    COMMAND "${CMAKE_COMMAND}"
        "-DBUNDLE=${CMAKE_INSTALL_PREFIX}"
        "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/embed"
        "-DWORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/embed"
        ${_praenora_pyenv_consumer_args}
        -P "${CMAKE_CURRENT_SOURCE_DIR}/run_embed.cmake")
add_test(NAME bundle.relocated
    COMMAND "${CMAKE_COMMAND}"
        "-DBUNDLE=${CMAKE_INSTALL_PREFIX}"
        "-DBUILD_DIR=${PROJECT_BINARY_DIR}"
        "-DSOURCE_DIR=${PROJECT_SOURCE_DIR}"
        "-DWORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/relocated"
        "-DPACKAGE_NAME=${PRAENORA_PYENV_PACKAGE_NAME}"
        ${_praenora_pyenv_consumer_args}
        -P "${CMAKE_CURRENT_SOURCE_DIR}/run_relocated.cmake")
set_tests_properties(bundle.embed bundle.relocated PROPERTIES TIMEOUT 1800)

# The drift report of tools/upstream_drift.py, against git repositories of the test's own.
add_test(NAME tools.drift
    COMMAND "${PRAENORA_PYENV_PYTHON_EXECUTABLE}" -I -B -m unittest discover
        -s "${CMAKE_CURRENT_SOURCE_DIR}/tools" -t "${CMAKE_CURRENT_SOURCE_DIR}/tools" -v
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")

# The documentation: links, anchors, and no local paths.
add_test(NAME docs.consistency
    COMMAND "${CMAKE_COMMAND}" "-DSOURCE_DIR=${PROJECT_SOURCE_DIR}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/check_docs.cmake")
