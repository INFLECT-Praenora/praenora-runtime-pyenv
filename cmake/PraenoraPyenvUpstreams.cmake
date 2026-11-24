# Checks of the upstream submodules against their pins (cmake/PraenoraPyenvVersions.cmake). Works
# in a configuration and in script mode.
#
# Defines:
#   praenora_pyenv_check_upstream(<name> <out_modified>)
#       Stops the configuration when the submodule of upstream <name> is missing or checked out at
#       another commit than PRAENORA_PYENV_<UP>_COMMIT (<UP>: <name> in upper case, '-' as '_').
#       PRAENORA_PYENV_<UP>_PATH is absolute or relative to PROJECT_SOURCE_DIR (the current
#       directory in script mode). Sets <out_modified> to true when tracked files of the
#       submodule differ from its commit, else to false; the manifest records it.

include_guard(GLOBAL)

find_package(Git QUIET)

function(praenora_pyenv_check_upstream name out_modified)
    if(NOT GIT_FOUND)
        message(FATAL_ERROR "Git is needed to check the upstream submodules.")
    endif()
    string(TOUPPER "${name}" _up)
    string(REPLACE "-" "_" _up "${_up}")
    set(_path "${PRAENORA_PYENV_${_up}_PATH}")
    set(_commit "${PRAENORA_PYENV_${_up}_COMMIT}")
    set(_ref "${PRAENORA_PYENV_${_up}_REF}")
    if(PROJECT_SOURCE_DIR)
        set(_base "${PROJECT_SOURCE_DIR}")
    else()
        set(_base "${CMAKE_CURRENT_SOURCE_DIR}")
    endif()
    cmake_path(ABSOLUTE_PATH _path BASE_DIRECTORY "${_base}" NORMALIZE OUTPUT_VARIABLE _dir)

    # A checked-out submodule has a .git file (or directory) at its top.
    if(NOT EXISTS "${_dir}/.git")
        message(FATAL_ERROR "${name}: ${_path} is missing; run git submodule update --init "
            "--recursive --depth 1")
    endif()
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${_dir}" rev-parse HEAD
        RESULT_VARIABLE _result OUTPUT_VARIABLE _head ERROR_VARIABLE _error
        OUTPUT_STRIP_TRAILING_WHITESPACE ENCODING UTF-8)
    if(NOT _result EQUAL 0)
        message(FATAL_ERROR "${name}: ${_path} is not a git checkout: ${_error}")
    endif()
    if(NOT _head STREQUAL _commit)
        message(FATAL_ERROR "${name}: ${_path} is at ${_head}, expected ${_commit} (${_ref}). "
            "Check out the pinned commit, or update the pin as docs/building.md"
            "#updating-an-upstream says.")
    endif()

    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${_dir}" status --porcelain
        --untracked-files=no
        RESULT_VARIABLE _result OUTPUT_VARIABLE _status ERROR_VARIABLE _error
        OUTPUT_STRIP_TRAILING_WHITESPACE ENCODING UTF-8)
    if(NOT _result EQUAL 0)
        message(FATAL_ERROR "${name}: git status failed in ${_path}: ${_error}")
    endif()
    if(_status STREQUAL "")
        set(${out_modified} false PARENT_SCOPE)
    else()
        message(WARNING "${name}: ${_path} has changes to tracked files; the manifest records "
            "the upstream as modified.")
        set(${out_modified} true PARENT_SCOPE)
    endif()
endfunction()

# praenora_pyenv_check_sources(<pyproject.toml> <what>)
#   Stops the configuration when a git source of PRAENORA_PYENV_VIVA_SOURCES (name=revision) is
#   missing from the [tool.uv.sources] table of <pyproject.toml>, or pinned there at another
#   revision. <what> names the file in the message.
function(praenora_pyenv_check_sources pyproject what)
    file(STRINGS "${pyproject}" _lines ENCODING UTF-8)
    foreach(_source IN LISTS PRAENORA_PYENV_VIVA_SOURCES)
        string(REPLACE "=" ";" _source "${_source}")
        list(GET _source 0 _name)
        list(GET _source 1 _revision)
        set(_found "")
        foreach(_line IN LISTS _lines)
            if(_line MATCHES "^${_name} *= *{.*rev *= *\"([0-9a-f]+)\"")
                set(_found "${CMAKE_MATCH_1}")
            endif()
        endforeach()
        if(_found STREQUAL "")
            message(FATAL_ERROR "${what} pins no revision of ${_name} in [tool.uv.sources]; "
                "PRAENORA_PYENV_VIVA_SOURCES expects ${_revision} (docs/upstreams.md).")
        elseif(NOT _found STREQUAL _revision)
            message(FATAL_ERROR "${what} pins ${_name} at ${_found}; "
                "PRAENORA_PYENV_VIVA_SOURCES expects ${_revision}. Use inflect-sim-core's "
                "revision in cmake/PraenoraPyenvVersions.cmake and pyproject.toml, then re-lock "
                "(docs/building.md#updating-an-upstream).")
        endif()
    endforeach()
endfunction()

# praenora_pyenv_require_tag(<name>)
#   Makes sure that the submodule of upstream <name> holds its pinned tag PRAENORA_PYENV_<UP>_REF
#   at its pinned commit: a submodule fetched without history has no tags, and BioGears takes its
#   version from `git describe --tags`. Fetches the one tag when it is missing, unless
#   PRAENORA_PYENV_OFFLINE is on; stops the configuration when the tag names another commit.
function(praenora_pyenv_require_tag name)
    string(TOUPPER "${name}" _up)
    string(REPLACE "-" "_" _up "${_up}")
    set(_dir "${PROJECT_SOURCE_DIR}/${PRAENORA_PYENV_${_up}_PATH}")
    set(_tag "${PRAENORA_PYENV_${_up}_REF}")
    set(_commit "${PRAENORA_PYENV_${_up}_COMMIT}")
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${_dir}" rev-parse -q --verify
        "refs/tags/${_tag}^{commit}"
        RESULT_VARIABLE _result OUTPUT_VARIABLE _tagged OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET ENCODING UTF-8)
    if(NOT _result EQUAL 0)
        set(_fetch "${GIT_EXECUTABLE}" -C "${_dir}" fetch --depth 1 --no-tags origin
            "refs/tags/${_tag}:refs/tags/${_tag}")
        list(JOIN _fetch " " _shown)
        if(PRAENORA_PYENV_OFFLINE)
            message(FATAL_ERROR "${name}: the submodule has no tag ${_tag}, from which it takes "
                "its version. Run: ${_shown}")
        endif()
        message(STATUS "praenora-runtime-pyenv: fetching the tag ${_tag} of ${name}")
        execute_process(COMMAND ${_fetch} RESULT_VARIABLE _result OUTPUT_VARIABLE _output
            ERROR_VARIABLE _output ENCODING UTF-8)
        if(NOT _result EQUAL 0)
            message(FATAL_ERROR "${name}: fetching the tag ${_tag} failed: ${_output}")
        endif()
        execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${_dir}" rev-parse -q --verify
            "refs/tags/${_tag}^{commit}"
            OUTPUT_VARIABLE _tagged OUTPUT_STRIP_TRAILING_WHITESPACE ENCODING UTF-8)
    endif()
    if(NOT _tagged STREQUAL _commit)
        message(FATAL_ERROR "${name}: the tag ${_tag} names ${_tagged}, not the pinned commit "
            "${_commit}.")
    endif()
endfunction()
