# The tools the build runs besides the compilers: uv, which locks and installs the Python
# distributions, and, for the engines that need them, Rust and CodeSynthesis XSD
# (docs/building.md#requirements).
#
# Defines:
#   PRAENORA_PYENV_UV_EXECUTABLE   (cache) uv; its version must be PRAENORA_PYENV_UV_VERSION
#   PRAENORA_PYENV_OFFLINE         (cache, OFF) every uv call with --offline
#   PRAENORA_PYENV_UV_CACHE_DIR    (cache) uv's cache; by default in the build tree, so that a
#                                  second build needs no network
#   PRAENORA_PYENV_UV_COMMAND      the command that runs uv, with its environment, as a list for
#                                  execute_process() and add_custom_command(); arguments follow
#   PRAENORA_PYENV_UV_OFFLINE_ARG  --offline with PRAENORA_PYENV_OFFLINE, else empty
#   praenora_pyenv_uv(<args>...)   runs uv at configuration time in the source directory and
#                                  stops the configuration when it fails, with its output
#   praenora_pyenv_check_lock(<python>)
#                                  stops the configuration when uv.lock does not match
#                                  pyproject.toml and the inflect-sim-core submodule
#   praenora_pyenv_check_engine_tools(<engines>)
#                                  finds the tools that the engines' builds need, and sets:
#   PRAENORA_PYENV_RUST_VERSION    rustc's version (engines that need Rust), else empty
#   PRAENORA_PYENV_XSD_EXECUTABLE  (cache) CodeSynthesis XSD (engines that need C++)
#   PRAENORA_PYENV_XSD_INCLUDE_DIR (cache) its header-only runtime library, libxsd
#   PRAENORA_PYENV_XSD_VERSION     its version, else empty
#   PRAENORA_PYENV_BUILD_PATH      PATH for the installation, with cargo's directory first when
#                                  Rust is needed and cargo is not on PATH (POSIX), else empty
#                                  (the caller's PATH)

include_guard(GLOBAL)

option(PRAENORA_PYENV_OFFLINE "Run uv offline: a download that a build needs is an error" OFF)

find_program(PRAENORA_PYENV_UV_EXECUTABLE uv
    HINTS "$ENV{HOME}/.local/bin" "$ENV{HOME}/.cargo/bin" "$ENV{USERPROFILE}/.local/bin"
    DOC "uv ${PRAENORA_PYENV_UV_VERSION}")
if(NOT PRAENORA_PYENV_UV_EXECUTABLE)
    message(FATAL_ERROR "uv ${PRAENORA_PYENV_UV_VERSION} is needed and was not found; install it "
        "(docs/building.md#requirements) or set PRAENORA_PYENV_UV_EXECUTABLE.")
endif()
execute_process(COMMAND "${PRAENORA_PYENV_UV_EXECUTABLE}" --version
    OUTPUT_VARIABLE _praenora_pyenv_uv_version OUTPUT_STRIP_TRAILING_WHITESPACE
    ENCODING UTF-8)
string(REGEX MATCH "^uv ([0-9.]+)" _praenora_pyenv_uv_match "${_praenora_pyenv_uv_version}")
if(NOT CMAKE_MATCH_1 STREQUAL PRAENORA_PYENV_UV_VERSION)
    message(FATAL_ERROR "${PRAENORA_PYENV_UV_EXECUTABLE} is '${_praenora_pyenv_uv_version}'; "
        "uv ${PRAENORA_PYENV_UV_VERSION} is needed (docs/building.md#requirements).")
endif()

set(PRAENORA_PYENV_UV_CACHE_DIR "${PROJECT_BINARY_DIR}/uv-cache" CACHE PATH
    "uv's cache directory (it holds git checkouts of the git sources of uv.lock)")
set(PRAENORA_PYENV_UV_OFFLINE_ARG "")
if(PRAENORA_PYENV_OFFLINE)
    set(PRAENORA_PYENV_UV_OFFLINE_ARG --offline)
endif()
# uv never downloads an interpreter (the bundle's comes from the pinned archive) and keeps its cache
# in PRAENORA_PYENV_UV_CACHE_DIR. It reads pyproject.toml's [tool.uv] table, which UV_NO_CONFIG
# would ignore.
set(PRAENORA_PYENV_UV_COMMAND "${CMAKE_COMMAND}" -E env
    "UV_CACHE_DIR=${PRAENORA_PYENV_UV_CACHE_DIR}"
    UV_PYTHON_DOWNLOADS=never
    "${PRAENORA_PYENV_UV_EXECUTABLE}")

function(praenora_pyenv_uv)
    execute_process(COMMAND ${PRAENORA_PYENV_UV_COMMAND} ${ARGN} ${PRAENORA_PYENV_UV_OFFLINE_ARG}
        WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
        RESULT_VARIABLE _result OUTPUT_VARIABLE _output ERROR_VARIABLE _output
        ENCODING UTF-8)
    if(NOT _result EQUAL 0)
        list(JOIN ARGN " " _arguments)
        message(FATAL_ERROR "uv ${_arguments} failed:\n${_output}")
    endif()
endfunction()

function(praenora_pyenv_check_lock python)
    execute_process(COMMAND ${PRAENORA_PYENV_UV_COMMAND} lock --check --python "${python}"
        ${PRAENORA_PYENV_UV_OFFLINE_ARG}
        WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
        RESULT_VARIABLE _result OUTPUT_VARIABLE _output ERROR_VARIABLE _output
        ENCODING UTF-8)
    if(NOT _result EQUAL 0)
        message(FATAL_ERROR "uv.lock does not match pyproject.toml or external/inflect-sim-core. "
            "Run uv lock, review the change of uv.lock and stage it with the change that caused "
            "it (docs/building.md#updating-an-upstream). uv reported:\n${_output}")
    endif()
endfunction()

# Rust: rustc and cargo of one toolchain, from PATH or rustup's default directory.
function(_praenora_pyenv_find_rust)
    find_program(PRAENORA_PYENV_CARGO_EXECUTABLE cargo
        HINTS "$ENV{CARGO_HOME}/bin" "$ENV{HOME}/.cargo/bin" "$ENV{USERPROFILE}/.cargo/bin"
        DOC "cargo of the Rust toolchain that builds viva-core")
    if(NOT PRAENORA_PYENV_CARGO_EXECUTABLE)
        message(FATAL_ERROR "The rust engine needs Rust ${PRAENORA_PYENV_RUST_MIN_VERSION} or "
            "newer (rustup, docs/building.md#requirements); cargo was not found. Install it, set "
            "PRAENORA_PYENV_CARGO_EXECUTABLE, or leave rust out of PRAENORA_PYENV_ENGINES.")
    endif()
    get_filename_component(_bin "${PRAENORA_PYENV_CARGO_EXECUTABLE}" DIRECTORY)
    find_program(_praenora_pyenv_rustc rustc HINTS "${_bin}" NO_DEFAULT_PATH)
    if(NOT _praenora_pyenv_rustc)
        message(FATAL_ERROR "rustc is not beside ${PRAENORA_PYENV_CARGO_EXECUTABLE}.")
    endif()
    execute_process(COMMAND "${_praenora_pyenv_rustc}" --version
        OUTPUT_VARIABLE _output OUTPUT_STRIP_TRAILING_WHITESPACE ENCODING UTF-8)
    string(REGEX MATCH "^rustc ([0-9]+\\.[0-9]+\\.[0-9]+)" _match "${_output}")
    set(_version "${CMAKE_MATCH_1}")
    if(_version STREQUAL "" OR _version VERSION_LESS PRAENORA_PYENV_RUST_MIN_VERSION)
        message(FATAL_ERROR "The rust engine needs Rust ${PRAENORA_PYENV_RUST_MIN_VERSION} or "
            "newer; ${_praenora_pyenv_rustc} is '${_output}'.")
    endif()
    # The installation finds cargo on PATH. On Windows, PATH's separator ';' cannot pass through
    # a custom command's arguments, so cargo must be on PATH already (rustup's installer does it).
    file(TO_CMAKE_PATH "$ENV{PATH}" _path)
    file(TO_CMAKE_PATH "${_bin}" _bin_path)
    if(NOT _bin_path IN_LIST _path)
        if(WIN32)
            message(FATAL_ERROR "Put ${_bin} on PATH before configuring: the build of viva-core "
                "runs cargo from PATH.")
        endif()
        set(PRAENORA_PYENV_BUILD_PATH "${_bin}:$ENV{PATH}" PARENT_SCOPE)
    endif()
    set(PRAENORA_PYENV_RUST_VERSION "${_version}" PARENT_SCOPE)
    message(STATUS "praenora-runtime-pyenv: Rust ${_version} (${_bin})")
endfunction()

# CodeSynthesis XSD: the compiler that generates BioGears' XML schema code, and libxsd, its
# header-only runtime library. Homebrew calls the compiler xsd, Debian and Ubuntu xsdcxx.
function(_praenora_pyenv_find_xsd)
    find_program(PRAENORA_PYENV_XSD_EXECUTABLE NAMES xsdcxx xsd
        DOC "CodeSynthesis XSD, which generates BioGears' schema code")
    if(NOT PRAENORA_PYENV_XSD_EXECUTABLE)
        message(FATAL_ERROR "The biogears engine needs CodeSynthesis XSD (Homebrew: xsd; "
            "Debian and Ubuntu: xsdcxx; docs/building.md#requirements). Install it, set "
            "PRAENORA_PYENV_XSD_EXECUTABLE, or leave biogears out of PRAENORA_PYENV_ENGINES.")
    endif()
    execute_process(COMMAND "${PRAENORA_PYENV_XSD_EXECUTABLE}" --version
        OUTPUT_VARIABLE _output ERROR_VARIABLE _output ENCODING UTF-8)
    if(NOT _output MATCHES "CodeSynthesis XSD[^\n]* ([0-9]+\\.[0-9]+\\.[0-9]+)")
        message(FATAL_ERROR "${PRAENORA_PYENV_XSD_EXECUTABLE} is not CodeSynthesis XSD (Mono "
            "installs another program named xsd); set PRAENORA_PYENV_XSD_EXECUTABLE.")
    endif()
    set(_version "${CMAKE_MATCH_1}")
    # libxsd from XSD's own installation (Homebrew's keg, not /opt/homebrew/include, which holds
    # other libraries' headers too, such as Homebrew's Xerces-C).
    get_filename_component(_real "${PRAENORA_PYENV_XSD_EXECUTABLE}" REALPATH)
    get_filename_component(_bin "${_real}" DIRECTORY)
    find_path(PRAENORA_PYENV_XSD_INCLUDE_DIR NAMES xsd/cxx/version.hxx
        HINTS "${_bin}/../include" NO_DEFAULT_PATH
        DOC "libxsd, CodeSynthesis XSD's runtime headers")
    find_path(PRAENORA_PYENV_XSD_INCLUDE_DIR NAMES xsd/cxx/version.hxx
        DOC "libxsd, CodeSynthesis XSD's runtime headers")
    if(NOT PRAENORA_PYENV_XSD_INCLUDE_DIR)
        message(FATAL_ERROR "The headers of CodeSynthesis XSD (xsd/cxx/version.hxx) were not "
            "found; set PRAENORA_PYENV_XSD_INCLUDE_DIR.")
    endif()
    set(PRAENORA_PYENV_XSD_VERSION "${_version}" PARENT_SCOPE)
    message(STATUS "praenora-runtime-pyenv: CodeSynthesis XSD ${_version} "
        "(${PRAENORA_PYENV_XSD_EXECUTABLE})")
endfunction()

macro(praenora_pyenv_check_engine_tools)
    set(PRAENORA_PYENV_RUST_VERSION "")
    set(PRAENORA_PYENV_XSD_VERSION "")
    set(PRAENORA_PYENV_BUILD_PATH "")
    foreach(_praenora_pyenv_engine IN ITEMS ${ARGN})
        string(TOUPPER "${_praenora_pyenv_engine}" _praenora_pyenv_engine_up)
        if(PRAENORA_PYENV_ENGINE_${_praenora_pyenv_engine_up}_NEEDS STREQUAL "rust" AND
           PRAENORA_PYENV_RUST_VERSION STREQUAL "")
            _praenora_pyenv_find_rust()
        endif()
        if(PRAENORA_PYENV_ENGINE_${_praenora_pyenv_engine_up}_NEEDS STREQUAL "cxx" AND
           PRAENORA_PYENV_XSD_VERSION STREQUAL "")
            _praenora_pyenv_find_xsd()
        endif()
    endforeach()
endmacro()

message(STATUS "praenora-runtime-pyenv: uv ${PRAENORA_PYENV_UV_VERSION} "
    "(${PRAENORA_PYENV_UV_EXECUTABLE})")
