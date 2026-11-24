# Test bundle.embed: configures and builds tests/embed in a fresh directory, with the bundle as its
# only CMAKE_PREFIX_PATH entry, then runs the program with the bundle's first SBML engine. The
# program runs with PYTHONPATH naming a directory whose viva_simulation_core.py raises, PYTHONHOME
# naming a directory that does not exist, and a current directory whose workspace.yaml names a
# package that cannot be imported: the embedded interpreter is isolated from all three.
#
#   cmake -DBUNDLE=<dir> -DVERSION=<v> -DSOURCE_DIR=<tests/embed> -DWORK_DIR=<dir>
#         -DGENERATOR=<g> -DCXX_COMPILER=<cxx> -DENGINES=<engines, separated by ','>
#         [-DOSX_ARCHITECTURES=<a>] -P tests/run_embed.cmake

cmake_minimum_required(VERSION 3.24)

foreach(_variable IN ITEMS BUNDLE VERSION SOURCE_DIR WORK_DIR GENERATOR CXX_COMPILER ENGINES)
    if(NOT DEFINED ${_variable} OR "${${_variable}}" STREQUAL "")
        message(FATAL_ERROR "${_variable} is not set")
    endif()
endforeach()
string(REPLACE "," ";" _engines "${ENGINES}")
string(REPLACE "," "|" _engines_bar "${ENGINES}")

file(REMOVE_RECURSE "${WORK_DIR}")
set(_build "${WORK_DIR}/build")
file(MAKE_DIRECTORY "${_build}")

# The caller's environment that the embedded interpreter must ignore.
set(_shadow "${WORK_DIR}/shadow")
file(WRITE "${_shadow}/viva_simulation_core.py"
    "raise ImportError('PYTHONPATH reached the embedded interpreter')\n")
set(_cwd "${WORK_DIR}/cwd")
file(WRITE "${_cwd}/workspace.yaml" "imports:\n  not-a-package: {}\n")

# The deployment target of the consumer: the bundle's, as its manifest states it.
file(READ "${BUNDLE}/praenora-runtime-pyenv.json" _manifest)
string(JSON _min_version ERROR_VARIABLE _error GET "${_manifest}" platform os_min_version)

string(REGEX MATCH "^[0-9]+\\.[0-9]+" _requested "${VERSION}")
set(_configure "${CMAKE_COMMAND}" -S "${SOURCE_DIR}" -B "${_build}" -G "${GENERATOR}"
    -DCMAKE_BUILD_TYPE=Release
    "-DCMAKE_CXX_COMPILER=${CXX_COMPILER}"
    "-DCMAKE_PREFIX_PATH=${BUNDLE}"
    "-DPRAENORA_PYENV_REQUESTED_VERSION=${_requested}"
    "-DPRAENORA_PYENV_TEST_ENGINES=${_engines_bar}")
if(OSX_ARCHITECTURES)
    list(APPEND _configure "-DCMAKE_OSX_ARCHITECTURES=${OSX_ARCHITECTURES}")
endif()
if(NOT _error AND NOT _min_version STREQUAL "" AND NOT _min_version STREQUAL "null")
    list(APPEND _configure "-DCMAKE_OSX_DEPLOYMENT_TARGET=${_min_version}")
endif()

set(_engine none)
foreach(_candidate IN ITEMS tellurium copasi)
    if(_candidate IN_LIST _engines)
        set(_engine ${_candidate})
        break()
    endif()
endforeach()
if(CMAKE_HOST_WIN32)
    set(_program "${_build}/praenora_pyenv_embed.exe")
else()
    set(_program "${_build}/praenora_pyenv_embed")
endif()

foreach(_step IN ITEMS configure build run)
    set(_directory "${WORK_DIR}")
    if(_step STREQUAL "configure")
        set(_command ${_configure})
    elseif(_step STREQUAL "build")
        set(_command "${CMAKE_COMMAND}" --build "${_build}")
    else()
        set(_command "${CMAKE_COMMAND}" -E env)
        if(CMAKE_HOST_WIN32)
            # python312.dll is beside the bundle's python.exe; Windows finds DLLs on PATH.
            file(TO_NATIVE_PATH "${BUNDLE}/python" _dll_dir)
            string(REPLACE ";" "\\;" _path "$ENV{PATH}")
            list(APPEND _command "PATH=${_dll_dir}\\;${_path}")
        endif()
        list(APPEND _command
            "PYTHONPATH=${_shadow}"
            "PYTHONHOME=${WORK_DIR}/no-such-home"
            "MPLCONFIGDIR=${WORK_DIR}/matplotlib"
            "${_program}" "${_engine}")
        set(_directory "${_cwd}")
    endif()
    list(JOIN _command " " _shown)
    message(STATUS "${_step}: ${_shown}")
    execute_process(COMMAND ${_command} WORKING_DIRECTORY "${_directory}"
        RESULT_VARIABLE _result OUTPUT_VARIABLE _output ERROR_VARIABLE _output
        ENCODING UTF-8)
    message("${_output}")
    if(NOT _result EQUAL 0)
        message(FATAL_ERROR "FAILED: ${_step} (${_result})")
    endif()
endforeach()

# The embedded interpreter wrote no bytecode into the bundle.
string(JSON _site GET "${_manifest}" python site_packages)
file(GLOB_RECURSE _bytecode LIST_DIRECTORIES false "${BUNDLE}/${_site}/*.pyc")
list(LENGTH _bytecode _count)
if(_count GREATER 0)
    list(GET _bytecode 0 _first)
    message(FATAL_ERROR "FAILED: ${_count} bytecode files in the bundle's site-packages, such as "
        "${_first}")
endif()
message(STATUS "ok: no bytecode in the bundle's site-packages")
