# Test bundle.relocated: copies the bundle to a directory whose path holds a space and a non-ASCII
# character, checks that no binary of the copy loads anything from the original location or the
# build tree (macOS), and runs the Python checks and the embedding program (run_embed.cmake) there.
#
#   cmake -DBUNDLE=<dir> -DBUILD_DIR=<dir> -DSOURCE_DIR=<repository> -DWORK_DIR=<dir>
#         -DPACKAGE_NAME=<name> -DENGINES=<engines, separated by ','> -DVERSION=<v>
#         -DGENERATOR=<g> -DCXX_COMPILER=<cxx> [-DOSX_ARCHITECTURES=<a>]
#         -P tests/run_relocated.cmake

cmake_minimum_required(VERSION 3.24)

foreach(_variable IN ITEMS BUNDLE BUILD_DIR SOURCE_DIR WORK_DIR PACKAGE_NAME ENGINES VERSION
                           GENERATOR CXX_COMPILER)
    if(NOT DEFINED ${_variable} OR "${${_variable}}" STREQUAL "")
        message(FATAL_ERROR "${_variable} is not set")
    endif()
endforeach()

file(REMOVE_RECURSE "${WORK_DIR}")
set(_moved "${WORK_DIR}/moved bundle é/${PACKAGE_NAME}")
file(MAKE_DIRECTORY "${_moved}")
file(COPY "${BUNDLE}/" DESTINATION "${_moved}" USE_SOURCE_PERMISSIONS)
message(STATUS "copied the bundle to ${_moved}")

# macOS: every load command and rpath of the copy's binaries is relative or a system path.
if(CMAKE_HOST_APPLE)
    file(GLOB_RECURSE _binaries LIST_DIRECTORIES false
        "${_moved}/*.so" "${_moved}/*.dylib" "${_moved}/python/bin/python3.12")
    set(_offenders "")
    foreach(_binary IN LISTS _binaries)
        if(IS_SYMLINK "${_binary}")
            continue()
        endif()
        execute_process(COMMAND otool -l "${_binary}" OUTPUT_VARIABLE _output ERROR_QUIET
            ENCODING UTF-8)
        # otool names the file itself, which lies in the build tree, in its headers.
        string(REPLACE "${_binary}" "" _output "${_output}")
        string(FIND "${_output}" "${BUNDLE}/" _in_bundle)
        string(FIND "${_output}" "${BUILD_DIR}/" _in_build)
        if(_in_bundle GREATER -1 OR _in_build GREATER -1)
            list(APPEND _offenders "${_binary}")
        endif()
    endforeach()
    list(LENGTH _binaries _count)
    if(_offenders)
        list(JOIN _offenders "\n  " _offenders)
        message(FATAL_ERROR "Binaries of the copy name the original bundle or the build "
            "tree:\n  ${_offenders}")
    endif()
    message(STATUS "ok: none of ${_count} binaries names the original bundle or the build tree")
endif()

# The Python checks, with the copy's interpreter.
string(REPLACE "," ";" _engines "${ENGINES}")
set(_environment "PRAENORA_PYENV_BUNDLE=${_moved}")
if(biogears IN_LIST _engines)
    list(APPEND _environment "BIOGEARS_RUNTIME=${_moved}/biogears/share/biogears/runtime")
endif()
if(CMAKE_HOST_WIN32)
    set(_python "${_moved}/python/python.exe")
else()
    set(_python "${_moved}/python/bin/python3.12")
endif()
message(STATUS "python checks: ${_python} -I -B -m unittest discover")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env ${_environment} "PRAENORA_PYENV_ENGINES=${_engines}"
        "${_python}" -I -B -m unittest discover -s "${SOURCE_DIR}/tests/python"
        -t "${SOURCE_DIR}/tests/python"
    WORKING_DIRECTORY "${WORK_DIR}"
    RESULT_VARIABLE _result OUTPUT_VARIABLE _output ERROR_VARIABLE _output ENCODING UTF-8)
message("${_output}")
if(NOT _result EQUAL 0)
    message(FATAL_ERROR "FAILED: the Python checks of the copy (${_result})")
endif()

# The embedding program, against the copy.
set(_embed "${CMAKE_COMMAND}" "-DBUNDLE=${_moved}" "-DVERSION=${VERSION}"
    "-DSOURCE_DIR=${SOURCE_DIR}/tests/embed" "-DWORK_DIR=${WORK_DIR}/embed"
    "-DGENERATOR=${GENERATOR}" "-DCXX_COMPILER=${CXX_COMPILER}" "-DENGINES=${ENGINES}")
if(OSX_ARCHITECTURES)
    list(APPEND _embed "-DOSX_ARCHITECTURES=${OSX_ARCHITECTURES}")
endif()
list(APPEND _embed -P "${SOURCE_DIR}/tests/run_embed.cmake")
execute_process(COMMAND ${_embed} RESULT_VARIABLE _result OUTPUT_VARIABLE _output
    ERROR_VARIABLE _output ENCODING UTF-8)
message("${_output}")
if(NOT _result EQUAL 0)
    message(FATAL_ERROR "FAILED: the embedding program against the copy (${_result})")
endif()
