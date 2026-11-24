# Test config.engines: praenora_pyenv_resolve_engines() (cmake/PraenoraPyenvEngines.cmake). Each
# case runs a child cmake -P, because the function stops a configuration with
# message(FATAL_ERROR).
#
#   cmake -DSOURCE_DIR=<repository> -DWORK_DIR=<directory> -P tests/check_engines.cmake

cmake_minimum_required(VERSION 3.24)

foreach(_variable IN ITEMS SOURCE_DIR WORK_DIR)
    if(NOT DEFINED ${_variable})
        message(FATAL_ERROR "${_variable} is not set")
    endif()
endforeach()
file(REMOVE_RECURSE "${WORK_DIR}")
file(MAKE_DIRECTORY "${WORK_DIR}")

set(_failures 0)
function(_case name os requested expected_result expected_output)
    set(_probe "${WORK_DIR}/probe-${name}.cmake")
    file(WRITE "${_probe}" "
include(\"${SOURCE_DIR}/cmake/PraenoraPyenvEngines.cmake\")
praenora_pyenv_resolve_engines(_engines OS ${os} REQUESTED \"${requested}\")
message(\"engines=\${_engines}\")
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

_case(macos_default macos "" 0 "engines=tellurium;copasi;biogears;rust")
_case(linux_default linux "" 0 "engines=tellurium;copasi;biogears;rust")
_case(windows_default windows "" 0 "engines=tellurium;copasi;rust")
_case(windows_biogears windows "biogears" 1 "biogears is not supported on windows")
_case(julia macos "julia" 1 "julia is not available upstream yet")
_case(unknown macos "foo" 1
    "unknown engine foo; known engines: tellurium, copasi, biogears, surrogate, rust, julia")
_case(order_and_duplicates macos "copasi;tellurium;copasi" 0 "engines=tellurium;copasi")
_case(surrogate macos "surrogate" 0 "engines=surrogate")

file(REMOVE_RECURSE "${WORK_DIR}")
if(_failures GREATER 0)
    message(FATAL_ERROR "${_failures} case(s) failed")
endif()
