# The bundle's CPython: python-build-standalone's archive for this platform
# (cmake/PraenoraPyenvVersions.cmake), downloaded, checked against its SHA-256 and unpacked into the
# build tree at configuration, where uv uses it to check the lock; the build copies it into the
# bundle (docs/building.md#what-the-build-does).
#
# Defines:
#   PRAENORA_PYENV_PYTHON_ARCHIVE      the archive's file name
#   PRAENORA_PYENV_PYTHON_SHA256       its SHA-256
#   PRAENORA_PYENV_PYTHON_STAGE        the unpacked interpreter in the build tree (its python/)
#   PRAENORA_PYENV_STAGE_EXECUTABLE    that interpreter's executable
#   PRAENORA_PYENV_PYTHON_HOME         the interpreter's directory in the bundle
#   PRAENORA_PYENV_PYTHON_EXECUTABLE   its executable there
#   PRAENORA_PYENV_PYTHON_EXECUTABLE_REL, _HOME_REL, _LIBRARY_REL, _INCLUDE_DIR_REL,
#   _SITE_PACKAGES_REL                 paths in the bundle, relative to it

include_guard(GLOBAL)

set(PRAENORA_PYENV_PYTHON_ARCHIVE
    "${PRAENORA_PYENV_PYTHON_${PRAENORA_PYENV_PLATFORM_KEY}_ARCHIVE}")
set(PRAENORA_PYENV_PYTHON_SHA256 "${PRAENORA_PYENV_PYTHON_${PRAENORA_PYENV_PLATFORM_KEY}_SHA256}")

set(PRAENORA_PYENV_PYTHON_HOME_REL "python")
if(WIN32)
    set(PRAENORA_PYENV_PYTHON_EXECUTABLE_REL "python/python.exe")
    set(PRAENORA_PYENV_PYTHON_LIBRARY_REL "python/libs/python312.lib")
    set(PRAENORA_PYENV_PYTHON_INCLUDE_DIR_REL "python/include")
    set(PRAENORA_PYENV_PYTHON_SITE_PACKAGES_REL "python/Lib/site-packages")
else()
    set(PRAENORA_PYENV_PYTHON_EXECUTABLE_REL "python/bin/python3.12")
    if(APPLE)
        set(PRAENORA_PYENV_PYTHON_LIBRARY_REL "python/lib/libpython3.12.dylib")
    else()
        set(PRAENORA_PYENV_PYTHON_LIBRARY_REL "python/lib/libpython3.12.so.1.0")
    endif()
    set(PRAENORA_PYENV_PYTHON_INCLUDE_DIR_REL "python/include/python3.12")
    set(PRAENORA_PYENV_PYTHON_SITE_PACKAGES_REL "python/lib/python3.12/site-packages")
endif()
set(PRAENORA_PYENV_PYTHON_HOME "${CMAKE_INSTALL_PREFIX}/${PRAENORA_PYENV_PYTHON_HOME_REL}")
set(PRAENORA_PYENV_PYTHON_EXECUTABLE
    "${CMAKE_INSTALL_PREFIX}/${PRAENORA_PYENV_PYTHON_EXECUTABLE_REL}")

# Download the archive, or reuse the one an earlier configuration downloaded when its SHA-256 is
# the pinned one.
set(_praenora_pyenv_downloads "${PROJECT_BINARY_DIR}/downloads")
set(_praenora_pyenv_archive "${_praenora_pyenv_downloads}/${PRAENORA_PYENV_PYTHON_ARCHIVE}")
set(_praenora_pyenv_have_archive FALSE)
if(EXISTS "${_praenora_pyenv_archive}")
    file(SHA256 "${_praenora_pyenv_archive}" _praenora_pyenv_sha256)
    if(_praenora_pyenv_sha256 STREQUAL PRAENORA_PYENV_PYTHON_SHA256)
        set(_praenora_pyenv_have_archive TRUE)
    else()
        file(REMOVE "${_praenora_pyenv_archive}")
    endif()
endif()
if(NOT _praenora_pyenv_have_archive)
    if(PRAENORA_PYENV_OFFLINE)
        message(FATAL_ERROR "PRAENORA_PYENV_OFFLINE is on and ${_praenora_pyenv_archive} is "
            "missing; configure once without it to download the CPython archive.")
    endif()
    string(REPLACE "+" "%2B" _praenora_pyenv_url_name "${PRAENORA_PYENV_PYTHON_ARCHIVE}")
    set(_praenora_pyenv_url "${PRAENORA_PYENV_PYTHON_BASE_URL}/${_praenora_pyenv_url_name}")
    message(STATUS "praenora-runtime-pyenv: downloading ${_praenora_pyenv_url}")
    file(DOWNLOAD "${_praenora_pyenv_url}" "${_praenora_pyenv_archive}.download"
        EXPECTED_HASH "SHA256=${PRAENORA_PYENV_PYTHON_SHA256}" TLS_VERIFY ON
        STATUS _praenora_pyenv_status)
    list(GET _praenora_pyenv_status 0 _praenora_pyenv_code)
    if(NOT _praenora_pyenv_code EQUAL 0)
        file(REMOVE "${_praenora_pyenv_archive}.download")
        message(FATAL_ERROR "Downloading ${_praenora_pyenv_url} failed: ${_praenora_pyenv_status}")
    endif()
    file(RENAME "${_praenora_pyenv_archive}.download" "${_praenora_pyenv_archive}")
endif()

# Unpack it once per archive; a stamp names the SHA-256 of the unpacked one.
set(_praenora_pyenv_stage_root "${PROJECT_BINARY_DIR}/python-stage")
set(PRAENORA_PYENV_PYTHON_STAGE "${_praenora_pyenv_stage_root}/python")
set(_praenora_pyenv_stamp "${_praenora_pyenv_stage_root}/unpacked.sha256")
set(_praenora_pyenv_unpacked "")
if(EXISTS "${_praenora_pyenv_stamp}")
    file(READ "${_praenora_pyenv_stamp}" _praenora_pyenv_unpacked)
endif()
if(NOT _praenora_pyenv_unpacked STREQUAL PRAENORA_PYENV_PYTHON_SHA256 OR
   NOT IS_DIRECTORY "${PRAENORA_PYENV_PYTHON_STAGE}")
    file(REMOVE_RECURSE "${_praenora_pyenv_stage_root}")
    file(ARCHIVE_EXTRACT INPUT "${_praenora_pyenv_archive}"
        DESTINATION "${_praenora_pyenv_stage_root}")
    if(NOT IS_DIRECTORY "${PRAENORA_PYENV_PYTHON_STAGE}")
        message(FATAL_ERROR "${PRAENORA_PYENV_PYTHON_ARCHIVE} holds no python/ directory.")
    endif()
    file(WRITE "${_praenora_pyenv_stamp}" "${PRAENORA_PYENV_PYTHON_SHA256}")
endif()
string(REPLACE "python/" "" _praenora_pyenv_executable_in_home
    "${PRAENORA_PYENV_PYTHON_EXECUTABLE_REL}")
set(PRAENORA_PYENV_STAGE_EXECUTABLE
    "${PRAENORA_PYENV_PYTHON_STAGE}/${_praenora_pyenv_executable_in_home}")
if(NOT EXISTS "${PRAENORA_PYENV_STAGE_EXECUTABLE}")
    message(FATAL_ERROR "${PRAENORA_PYENV_PYTHON_ARCHIVE} holds no "
        "${_praenora_pyenv_executable_in_home}.")
endif()
message(STATUS "praenora-runtime-pyenv: CPython ${PRAENORA_PYENV_PYTHON_VERSION} from "
    "${PRAENORA_PYENV_PYTHON_ARCHIVE}")
