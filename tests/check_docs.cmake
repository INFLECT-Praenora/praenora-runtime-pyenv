# Test docs.consistency: every relative Markdown link of README.md, AGENTS.md and docs/ resolves,
# with its #anchor; no file of the repository's own names a path on a developer's machine; and the
# agent instructions live in AGENTS.md only (no CLAUDE.md).
#
#   cmake -DSOURCE_DIR=<repository> -P tests/check_docs.cmake

cmake_minimum_required(VERSION 3.24)

if(NOT DEFINED SOURCE_DIR)
    message(FATAL_ERROR "SOURCE_DIR is not set")
endif()

set(_failures 0)
function(_fail what)
    message(STATUS "FAILED: ${what}")
    math(EXPR _count "${_failures} + 1")
    set(_failures ${_count} PARENT_SCOPE)
endfunction()

# GitHub's anchor of a heading: lower case, punctuation removed, spaces as '-'.
function(_anchors out file)
    file(STRINGS "${file}" _headings REGEX "^#+ " ENCODING UTF-8)
    set(_anchors "")
    foreach(_heading IN LISTS _headings)
        string(REGEX REPLACE "^#+ +" "" _heading "${_heading}")
        string(TOLOWER "${_heading}" _heading)
        string(REGEX REPLACE "[^a-z0-9 _-]" "" _heading "${_heading}")
        string(REPLACE " " "-" _heading "${_heading}")
        list(APPEND _anchors "${_heading}")
    endforeach()
    set(${out} "${_anchors}" PARENT_SCOPE)
endfunction()

file(GLOB _documents "${SOURCE_DIR}/README.md" "${SOURCE_DIR}/AGENTS.md" "${SOURCE_DIR}/docs/*.md")
foreach(_document IN LISTS _documents)
    file(READ "${_document}" _text)
    get_filename_component(_directory "${_document}" DIRECTORY)
    file(RELATIVE_PATH _name "${SOURCE_DIR}" "${_document}")
    # CMake lists group what square brackets enclose, so the link syntax "](" becomes a token
    # without brackets before the links are matched.
    string(REPLACE "](" "<link>(" _text "${_text}")
    string(REGEX MATCHALL "<link>\\([^)]+\\)" _links "${_text}")
    foreach(_link IN LISTS _links)
        string(REGEX REPLACE "^<link>\\((.*)\\)$" "\\1" _target "${_link}")
        if(_target MATCHES "^(https?|mailto):")
            continue()
        endif()
        set(_anchor "")
        if(_target MATCHES "^([^#]*)#(.*)$")
            set(_target "${CMAKE_MATCH_1}")
            set(_anchor "${CMAKE_MATCH_2}")
        endif()
        if(_target STREQUAL "")
            set(_path "${_document}")
        else()
            set(_path "${_directory}/${_target}")
        endif()
        if(NOT EXISTS "${_path}")
            _fail("${_name}: the link target ${_target} does not exist")
            continue()
        endif()
        if(NOT _anchor STREQUAL "" AND _path MATCHES "\\.md$")
            _anchors(_known "${_path}")
            if(NOT _anchor IN_LIST _known)
                _fail("${_name}: ${_target} has no heading #${_anchor}")
            endif()
        endif()
    endforeach()
endforeach()

# No path of a developer's machine in the repository's own files.
file(GLOB_RECURSE _files LIST_DIRECTORIES false
    "${SOURCE_DIR}/*.md" "${SOURCE_DIR}/cmake/*" "${SOURCE_DIR}/tests/*" "${SOURCE_DIR}/tools/*"
    "${SOURCE_DIR}/.github/*" "${SOURCE_DIR}/pyproject.toml" "${SOURCE_DIR}/CMakeLists.txt"
    "${SOURCE_DIR}/CMakePresets.json")
list(FILTER _files EXCLUDE REGEX "^${SOURCE_DIR}/(external|build|install)/")
list(FILTER _files EXCLUDE REGEX "/tests/check_docs\\.cmake$")
foreach(_file IN LISTS _files)
    file(STRINGS "${_file}" _hits ENCODING UTF-8
        REGEX "/Users/[A-Za-z]|/home/[a-z]|[A-Za-z]:\\\\Users\\\\|PycharmProjects")
    if(_hits)
        file(RELATIVE_PATH _name "${SOURCE_DIR}" "${_file}")
        list(GET _hits 0 _hit)
        _fail("${_name} names a local path: ${_hit}")
    endif()
endforeach()

if(EXISTS "${SOURCE_DIR}/CLAUDE.md")
    _fail("CLAUDE.md exists; agent instructions live in AGENTS.md")
endif()

list(LENGTH _documents _count)
if(_failures GREATER 0)
    message(FATAL_ERROR "${_failures} check(s) failed in ${_count} documents")
endif()
message(STATUS "ok: ${_count} documents, their links and the repository's files")
