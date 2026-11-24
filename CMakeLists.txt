cmake_minimum_required(VERSION 3.24)

# The macOS deployment target of everything the build compiles. It is a cache default set before
# project(), as in the Praenora runtime and praenora-runtime-deps
# (docs/outputs.md#names).
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING
    "Minimum macOS version of what the build compiles (macOS only)")

project(praenora_runtime_pyenv
    VERSION 0.1.0
    DESCRIPTION "Python environment of the Praenora runtime"
    HOMEPAGE_URL "https://github.com/INFLECT-Praenora/praenora-runtime-pyenv"
    LANGUAGES C CXX)

list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake")

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX "${PROJECT_BINARY_DIR}/install" CACHE PATH
        "Directory the Python environment bundle is written to during the build" FORCE)
endif()

include(PraenoraPyenvVersions)
include(PraenoraPyenvPlatform)
include(PraenoraPyenvUpstreams)
include(PraenoraPyenvEngines)
include(PraenoraPyenvTools)
include(PraenoraPyenvInterpreter)

# The upstream submodules at their pins (docs/upstreams.md). A file per upstream names its commit;
# it changes when the pin does, which rebuilds what is built from the upstream.
foreach(_upstream IN LISTS PRAENORA_PYENV_UPSTREAMS)
    string(TOUPPER "${_upstream}" _up)
    string(REPLACE "-" "_" _up "${_up}")
    praenora_pyenv_check_upstream(${_upstream} PRAENORA_PYENV_${_up}_MODIFIED)
    set(PRAENORA_PYENV_${_up}_COMMIT_FILE "${PROJECT_BINARY_DIR}/stamps/${_upstream}.commit")
    file(CONFIGURE OUTPUT "${PRAENORA_PYENV_${_up}_COMMIT_FILE}"
        CONTENT "${PRAENORA_PYENV_${_up}_COMMIT}\n")
endforeach()
praenora_pyenv_check_sources("${PROJECT_SOURCE_DIR}/external/inflect-sim-core/pyproject.toml"
    "inflect-sim-core's pyproject.toml")
praenora_pyenv_check_sources("${PROJECT_SOURCE_DIR}/pyproject.toml" "pyproject.toml")

# The engines (docs/building.md#options).
set(PRAENORA_PYENV_ENGINES "" CACHE STRING
    "Engines of the bundle, separated by ';'; empty for the platform's default")
praenora_pyenv_resolve_engines(PRAENORA_PYENV_ENGINES_RESOLVED OS ${PRAENORA_PYENV_OS}
    REQUESTED "${PRAENORA_PYENV_ENGINES}")
list(JOIN PRAENORA_PYENV_ENGINES_RESOLVED ", " _engines)
message(STATUS "praenora-runtime-pyenv: engines ${_engines}")
praenora_pyenv_check_engine_tools(${PRAENORA_PYENV_ENGINES_RESOLVED})
if(biogears IN_LIST PRAENORA_PYENV_ENGINES_RESOLVED)
    # BioGears takes its version from its tag (docs/upstreams.md#biogears).
    praenora_pyenv_require_tag(biogears)
endif()

# The lock matches pyproject.toml and the inflect-sim-core submodule.
praenora_pyenv_check_lock("${PRAENORA_PYENV_STAGE_EXECUTABLE}")

# The native build of the biogears engine, then the Python environment.
if(biogears IN_LIST PRAENORA_PYENV_ENGINES_RESOLVED)
    include(PraenoraPyenvNative)
endif()
include(PraenoraPyenvEnvironment)
if(TARGET pyenv_biogears_bundle)
    praenora_pyenv_environment_depends(pyenv_biogears_bundle)
endif()

# The bundle step and the archive.
include(PraenoraPyenvPackage)

enable_testing()
add_subdirectory(tests)
