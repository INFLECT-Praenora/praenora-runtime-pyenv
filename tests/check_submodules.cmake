# Test config.submodules: praenora_pyenv_check_upstream() (cmake/PraenoraPyenvUpstreams.cmake)
# against a temporary git repository with two commits. Each case runs a child cmake -P, because
# the function stops a configuration with message(FATAL_ERROR). The repository is made under the
# system temporary directory, not in the build tree: a git repository nested in this checkout
# confuses git tools, and some sandboxes refuse to write a nested .git/config.
#
#   cmake -DSOURCE_DIR=<repository> -P tests/check_submodules.cmake

cmake_minimum_required(VERSION 3.24)

if(NOT DEFINED SOURCE_DIR)
    message(FATAL_ERROR "SOURCE_DIR is not set")
endif()
find_package(Git REQUIRED)

set(_temp "")
foreach(_candidate IN ITEMS "$ENV{TMPDIR}" "$ENV{TEMP}" "$ENV{TMP}" "/tmp")
    if(NOT _candidate STREQUAL "" AND IS_DIRECTORY "${_candidate}")
        set(_temp "${_candidate}")
        break()
    endif()
endforeach()
if(_temp STREQUAL "")
    message(FATAL_ERROR "No temporary directory found (TMPDIR, TEMP, TMP, /tmp)")
endif()
string(RANDOM LENGTH 8 _suffix)
set(WORK_DIR "${_temp}/praenora-pyenv-submodules-${_suffix}")

set(_repo "${WORK_DIR}/upstream")
file(REMOVE_RECURSE "${WORK_DIR}")
file(MAKE_DIRECTORY "${_repo}")

function(_git)
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${_repo}" -c user.name=test
        -c user.email=test@invalid -c commit.gpgsign=false ${ARGN}
        RESULT_VARIABLE _result OUTPUT_VARIABLE _output ERROR_VARIABLE _output
        ENCODING UTF-8)
    if(NOT _result EQUAL 0)
        message(FATAL_ERROR "git ${ARGN} failed: ${_output}")
    endif()
endfunction()

function(_head out)
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${_repo}" rev-parse HEAD
        OUTPUT_VARIABLE _output OUTPUT_STRIP_TRAILING_WHITESPACE ENCODING UTF-8)
    set(${out} "${_output}" PARENT_SCOPE)
endfunction()

_git(init -q --template=)
file(WRITE "${_repo}/file.txt" "one\n")
_git(add file.txt)
_git(commit -q -m one)
_head(_first)
file(WRITE "${_repo}/file.txt" "two\n")
_git(commit -q -a -m two)
_head(_second)

# Runs the function in a child cmake and checks its exit code and output.
set(_failures 0)
function(_case name path commit expected_result expected_output)
    set(_probe "${WORK_DIR}/probe-${name}.cmake")
    file(WRITE "${_probe}" "
include(\"${SOURCE_DIR}/cmake/PraenoraPyenvUpstreams.cmake\")
set(PRAENORA_PYENV_PROBE_PATH \"${path}\")
set(PRAENORA_PYENV_PROBE_COMMIT \"${commit}\")
set(PRAENORA_PYENV_PROBE_REF \"test-ref\")
praenora_pyenv_check_upstream(probe _modified)
message(\"modified=\${_modified}\")
")
    execute_process(COMMAND "${CMAKE_COMMAND}" -P "${_probe}"
        RESULT_VARIABLE _result OUTPUT_VARIABLE _output ERROR_VARIABLE _output
        ENCODING UTF-8)
    # CMake wraps long messages over lines; compare with whitespace collapsed.
    string(REGEX REPLACE "[ \t\r\n]+" " " _flat "${_output}")
    string(FIND "${_flat}" "${expected_output}" _found)
    set(_exit_ok FALSE)
    if(_result EQUAL 0 AND expected_result EQUAL 0)
        set(_exit_ok TRUE)
    elseif(NOT _result EQUAL 0 AND NOT expected_result EQUAL 0)
        set(_exit_ok TRUE)
    endif()
    if(_exit_ok AND _found GREATER -1)
        message(STATUS "ok: ${name}")
    else()
        message(STATUS "FAILED: ${name} (exit ${_result}, expected ${expected_result}, "
            "expected output containing '${expected_output}'):\n${_output}")
        math(EXPR _count "${_failures} + 1")
        set(_failures ${_count} PARENT_SCOPE)
    endif()
endfunction()

_case(clean_at_pin "${_repo}" "${_second}" 0 "modified=false")
file(WRITE "${_repo}/file.txt" "changed\n")
_case(modified_at_pin "${_repo}" "${_second}" 0 "modified=true")
_git(checkout -q -- file.txt)
_case(other_commit "${_repo}" "${_first}" 1 "is at ${_second}, expected ${_first} (test-ref)")
_case(missing "${WORK_DIR}/missing" "${_first}" 1
    "is missing; run git submodule update --init --recursive --depth 1")

file(REMOVE_RECURSE "${WORK_DIR}")
if(_failures GREATER 0)
    message(FATAL_ERROR "${_failures} case(s) failed")
endif()
