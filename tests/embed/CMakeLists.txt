# A consumer of a bundle (test bundle.embed): finds it through find_package(PraenoraRuntimePyenv)
# with the bundle as its only prefix, finds the bundle's CPython for embedding through
# Python3_ROOT_DIR, builds a program that embeds it, and checks that the bundle's CMake package
# refuses requests it cannot satisfy.
#
# PRAENORA_PYENV_REQUESTED_VERSION: MAJOR.MINOR to request. PRAENORA_PYENV_TEST_ENGINES: the
# bundle's engines, separated by '|'.

cmake_minimum_required(VERSION 3.24)
project(praenora_pyenv_embed LANGUAGES CXX)

string(REPLACE "|" ";" engines "${PRAENORA_PYENV_TEST_ENGINES}")
find_package(PraenoraRuntimePyenv ${PRAENORA_PYENV_REQUESTED_VERSION} CONFIG REQUIRED
    COMPONENTS ${engines})
message(STATUS "PraenoraRuntimePyenv ${PraenoraRuntimePyenv_VERSION} at "
    "${PraenoraRuntimePyenv_ROOT} (${PraenoraRuntimePyenv_PACKAGE_NAME})")

# The bundle's CPython, and no other.
set(Python3_ROOT_DIR "${PraenoraRuntimePyenv_PYTHON_HOME}")
set(Python3_FIND_STRATEGY LOCATION)
set(Python3_FIND_REGISTRY NEVER)
set(Python3_FIND_FRAMEWORK NEVER)
set(Python3_FIND_VIRTUALENV STANDARD)
find_package(Python3 ${PraenoraRuntimePyenv_PYTHON_VERSION} EXACT REQUIRED
    COMPONENTS Development.Embed)
foreach(path IN LISTS Python3_INCLUDE_DIRS Python3_LIBRARIES)
    cmake_path(IS_PREFIX PraenoraRuntimePyenv_ROOT "${path}" NORMALIZE inside)
    if(NOT inside)
        message(FATAL_ERROR "Python3 was found at ${path}, outside the bundle "
            "(${PraenoraRuntimePyenv_ROOT}).")
    endif()
endforeach()
message(STATUS "Python3 ${Python3_VERSION}: ${Python3_LIBRARIES}")

add_executable(praenora_pyenv_embed embed.cpp)
target_compile_features(praenora_pyenv_embed PRIVATE cxx_std_17)
target_link_libraries(praenora_pyenv_embed PRIVATE Python3::Python)
target_compile_definitions(praenora_pyenv_embed PRIVATE
    "PRAENORA_PYENV_PYTHON_HOME=\"${PraenoraRuntimePyenv_PYTHON_HOME}\""
    "PRAENORA_PYENV_PYTHON_EXECUTABLE=\"${PraenoraRuntimePyenv_PYTHON_EXECUTABLE}\"")
# PyConfig_SetBytesString and PyRun_SimpleString read the paths as UTF-8; MSVC encodes string
# literals in the ANSI code page unless told otherwise.
if(MSVC)
    target_compile_options(praenora_pyenv_embed PRIVATE /utf-8)
endif()
# Windows refuses paths longer than 260 characters to a program whose manifest does not declare it
# long-path-aware; a bundle's deepest files exceed that in a deep directory. CMake embeds the
# manifest in the program.
if(WIN32)
    target_sources(praenora_pyenv_embed PRIVATE embed.manifest)
endif()
if(NOT WIN32)
    set_target_properties(praenora_pyenv_embed PROPERTIES
        BUILD_RPATH "${PraenoraRuntimePyenv_PYTHON_HOME}/lib")
endif()

# The package refuses what the bundle cannot satisfy. Each case overrides variables in a function
# scope only.
function(expect_refused description version)
    cmake_parse_arguments(PARSE_ARGV 2 arg "" "" "COMPONENTS;SET")
    foreach(assignment IN LISTS arg_SET)
        string(REGEX MATCH "^([^=]+)=(.*)$" _ "${assignment}")
        set(${CMAKE_MATCH_1} "${CMAKE_MATCH_2}")
    endforeach()
    unset(PraenoraRuntimePyenv_FOUND)
    if(arg_COMPONENTS)
        find_package(PraenoraRuntimePyenv ${version} CONFIG QUIET COMPONENTS ${arg_COMPONENTS})
    else()
        find_package(PraenoraRuntimePyenv ${version} CONFIG QUIET)
    endif()
    if(PraenoraRuntimePyenv_FOUND)
        message(FATAL_ERROR "The bundle was accepted for ${description}.")
    endif()
    message(STATUS "Refused as expected: ${description}")
endfunction()

string(REGEX MATCH "^([0-9]+)\\.([0-9]+)" _ "${PraenoraRuntimePyenv_VERSION}")
math(EXPR newer_minor "${CMAKE_MATCH_2} + 1")
math(EXPR newer_major "${CMAKE_MATCH_1} + 1")
expect_refused("version ${CMAKE_MATCH_1}.${newer_minor}" "${CMAKE_MATCH_1}.${newer_minor}")
expect_refused("version ${newer_major}.0" "${newer_major}.0")
if(PraenoraRuntimePyenv_OS STREQUAL "linux")
    expect_refused("another operating system" "" SET CMAKE_SYSTEM_NAME=Windows)
else()
    expect_refused("another operating system" "" SET CMAKE_SYSTEM_NAME=Linux)
endif()
if(PraenoraRuntimePyenv_ARCH STREQUAL "arm64")
    set(other_arch x86_64)
else()
    set(other_arch arm64)
endif()
expect_refused("another architecture" "" SET
    CMAKE_OSX_ARCHITECTURES=${other_arch} CMAKE_SYSTEM_PROCESSOR=${other_arch}
    CMAKE_CXX_COMPILER_ARCHITECTURE_ID=${other_arch})
if(PraenoraRuntimePyenv_OS_MIN_VERSION AND PraenoraRuntimePyenv_OS_MIN_VERSION VERSION_GREATER 11.0)
    expect_refused("macOS deployment target 11.0" "" SET CMAKE_OSX_DEPLOYMENT_TARGET=11.0)
endif()
foreach(engine IN ITEMS surrogate biogears rust tellurium copasi)
    if(NOT engine IN_LIST PraenoraRuntimePyenv_ENGINES)
        expect_refused("the engine ${engine}, which the bundle does not hold" ""
            COMPONENTS ${engine})
        break()
    endif()
endforeach()
