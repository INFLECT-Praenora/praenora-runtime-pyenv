# The build of the Python environment: the staged CPython (cmake/PraenoraPyenvInterpreter.cmake)
# copied into the bundle, then the distributions of uv.lock for the enabled engines installed into
# that interpreter's own site-packages, without resolving anything (docs/building.md).
#
# Defines:
#   targets pyenv_interpreter, pyenv_environment (both built by default)
#   praenora_pyenv_environment_depends(<target>...)
#       makes the installation wait for targets that build what it compiles against, such as
#       BioGears for pybiogears
#   PRAENORA_PYENV_ENVIRONMENT_STAMP   the file that the installation's custom command writes

include_guard(GLOBAL)

set(_praenora_pyenv_stamps "${PROJECT_BINARY_DIR}/stamps")
file(MAKE_DIRECTORY "${_praenora_pyenv_stamps}")

# The interpreter: a fresh copy, with its symbolic links, whenever the staged archive changes,
# which also reinstalls the environment.
set(_praenora_pyenv_interpreter_stamp "${_praenora_pyenv_stamps}/interpreter.stamp")
add_custom_command(OUTPUT "${_praenora_pyenv_interpreter_stamp}"
    COMMAND "${CMAKE_COMMAND}" "-DSOURCE=${PRAENORA_PYENV_PYTHON_STAGE}"
        "-DDESTINATION=${PRAENORA_PYENV_PYTHON_HOME}"
        -P "${PROJECT_SOURCE_DIR}/cmake/praenora_pyenv_copy_tree.cmake"
    COMMAND "${CMAKE_COMMAND}" -E touch "${_praenora_pyenv_interpreter_stamp}"
    DEPENDS "${PROJECT_BINARY_DIR}/python-stage/unpacked.sha256"
        "${PROJECT_SOURCE_DIR}/cmake/praenora_pyenv_copy_tree.cmake"
    COMMENT "Copying CPython ${PRAENORA_PYENV_PYTHON_VERSION} into the bundle"
    VERBATIM)
add_custom_target(pyenv_interpreter ALL DEPENDS "${_praenora_pyenv_interpreter_stamp}")

# The extras of the enabled engines.
set(_praenora_pyenv_extras "")
foreach(_praenora_pyenv_engine IN LISTS PRAENORA_PYENV_ENGINES_RESOLVED)
    string(TOUPPER "${_praenora_pyenv_engine}" _praenora_pyenv_engine_up)
    list(APPEND _praenora_pyenv_extras
        --extra "${PRAENORA_PYENV_ENGINE_${_praenora_pyenv_engine_up}_EXTRA}")
endforeach()

# A file that changes when the engines change, so that the installation runs again.
set(_praenora_pyenv_engines_file "${_praenora_pyenv_stamps}/engines.txt")
file(CONFIGURE OUTPUT "${_praenora_pyenv_engines_file}"
    CONTENT "${PRAENORA_PYENV_ENGINES_RESOLVED}\n")

# The environment of the installation. Distributions built from source (viva-core, pybiogears)
# use the project's compilers and macOS deployment target. Files are copied from uv's cache, never
# linked to it.
set(_praenora_pyenv_sync_env
    "UV_PROJECT_ENVIRONMENT=${PRAENORA_PYENV_PYTHON_HOME}"
    UV_LINK_MODE=copy
    "CC=${CMAKE_C_COMPILER}"
    "CXX=${CMAKE_CXX_COMPILER}")
if(APPLE)
    list(APPEND _praenora_pyenv_sync_env
        "MACOSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}")
endif()
if(PRAENORA_PYENV_BUILD_PATH)
    list(APPEND _praenora_pyenv_sync_env "PATH=${PRAENORA_PYENV_BUILD_PATH}")
endif()
# uv reuses its build of a path source while the source's pyproject.toml is unchanged, so
# simulation-core is reinstalled from its submodule each time, and a new commit of a submodule
# installs the environment again. pybiogears is compiled against BioGears: uv's cached build of it
# is not reused either, and a new build of BioGears installs the environment again. Its build
# (scikit-build-core) gets BioGears' CMake package in the build tree and the Eigen, Xerces-C and
# XSD that BioGears was built with as CMake definitions, so that it finds none of the build
# machine's own.
set(_praenora_pyenv_sync_args --reinstall-package simulation-core)
set(_praenora_pyenv_sync_depends "${PRAENORA_PYENV_INFLECT_SIM_CORE_COMMIT_FILE}")
if(biogears IN_LIST PRAENORA_PYENV_ENGINES_RESOLVED)
    foreach(_praenora_pyenv_definition IN ITEMS
            "Biogears_DIR=${PRAENORA_PYENV_BIOGEARS_PREFIX}/lib/cmake/Biogears"
            ${PRAENORA_PYENV_BIOGEARS_DEPENDENCIES})
        list(APPEND _praenora_pyenv_sync_args --config-settings-package
            "pybiogears:cmake.define.${_praenora_pyenv_definition}")
    endforeach()
    list(APPEND _praenora_pyenv_sync_args --reinstall-package pybiogears)
    list(APPEND _praenora_pyenv_sync_depends
        "${PROJECT_BINARY_DIR}/stamps/biogears-bundle.stamp"
        "${PRAENORA_PYENV_PYBIOGEARS_COMMIT_FILE}")
endif()

set(PRAENORA_PYENV_ENVIRONMENT_STAMP "${_praenora_pyenv_stamps}/environment.stamp")
add_custom_command(OUTPUT "${PRAENORA_PYENV_ENVIRONMENT_STAMP}"
    COMMAND "${CMAKE_COMMAND}" -E env ${_praenora_pyenv_sync_env}
        ${PRAENORA_PYENV_UV_COMMAND} sync --frozen --no-install-project
        --python "${PRAENORA_PYENV_PYTHON_EXECUTABLE}" ${_praenora_pyenv_extras}
        ${_praenora_pyenv_sync_args} ${PRAENORA_PYENV_UV_OFFLINE_ARG}
    COMMAND "${CMAKE_COMMAND}" -E touch "${PRAENORA_PYENV_ENVIRONMENT_STAMP}"
    DEPENDS "${_praenora_pyenv_interpreter_stamp}" "${_praenora_pyenv_engines_file}"
        "${PROJECT_SOURCE_DIR}/uv.lock" "${PROJECT_SOURCE_DIR}/pyproject.toml"
        ${_praenora_pyenv_sync_depends}
    WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
    COMMENT "Installing the Python distributions of uv.lock into the bundle"
    USES_TERMINAL
    VERBATIM)
add_custom_target(pyenv_environment ALL DEPENDS "${PRAENORA_PYENV_ENVIRONMENT_STAMP}")
add_dependencies(pyenv_environment pyenv_interpreter)

function(praenora_pyenv_environment_depends)
    add_dependencies(pyenv_environment ${ARGN})
endfunction()
