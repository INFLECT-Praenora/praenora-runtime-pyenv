# The bundle step, in script mode: checks the installed distributions, copies the license files,
# makes the bundle relocatable, and writes the manifest and the CMake package
# (docs/building.md#what-the-build-does, docs/outputs.md). The target pyenv_bundle
# (cmake/PraenoraPyenvPackage.cmake) runs it after the installation:
#
#   cmake -DCONFIG=<build>/bundle-config.cmake -P cmake/PraenoraPyenvBundle.cmake
#
# CONFIG sets the build's values (see PraenoraPyenvPackage.cmake); the pins come from
# cmake/PraenoraPyenvVersions.cmake. Each check that fails stops the step with message(FATAL_ERROR).

cmake_minimum_required(VERSION 3.24)

if(NOT DEFINED CONFIG OR NOT EXISTS "${CONFIG}")
    message(FATAL_ERROR "PraenoraPyenvBundle.cmake: CONFIG does not name a file")
endif()
include("${CONFIG}")
include("${PROJECT_SOURCE_DIR}/cmake/PraenoraPyenvVersions.cmake")

set(BUNDLE "${CMAKE_INSTALL_PREFIX}")
set(SITE "${BUNDLE}/${PRAENORA_PYENV_PYTHON_SITE_PACKAGES_REL}")
set(LICENSES "${BUNDLE}/licenses")

function(_run)
    execute_process(COMMAND ${ARGN} RESULT_VARIABLE _result OUTPUT_VARIABLE _output
        ERROR_VARIABLE _output ENCODING UTF-8)
    if(NOT _result EQUAL 0)
        list(JOIN ARGN " " _command)
        message(FATAL_ERROR "${_command} failed: ${_output}")
    endif()
endfunction()

# A JSON string literal of a value.
function(_json_string out value)
    string(REPLACE "\\" "\\\\" value "${value}")
    string(REPLACE "\"" "\\\"" value "${value}")
    string(REPLACE "\n" "\\n" value "${value}")
    string(REPLACE "\r" "\\r" value "${value}")
    string(REPLACE "\t" "\\t" value "${value}")
    set(${out} "\"${value}\"" PARENT_SCOPE)
endfunction()
# A JSON string literal, or null for an empty value.
function(_json_nullable out value)
    if("${value}" STREQUAL "")
        set(${out} "null" PARENT_SCOPE)
    else()
        _json_string(_literal "${value}")
        set(${out} "${_literal}" PARENT_SCOPE)
    endif()
endfunction()
# A JSON array of string literals.
function(_json_array out)
    set(_items "")
    foreach(_item IN LISTS ARGN)
        _json_string(_literal "${_item}")
        list(APPEND _items "${_literal}")
    endforeach()
    list(JOIN _items ", " _items)
    set(${out} "[${_items}]" PARENT_SCOPE)
endfunction()
# The normalized name of a distribution (PEP 503).
function(_normalize out name)
    string(TOLOWER "${name}" name)
    string(REGEX REPLACE "[-_.]+" "-" name "${name}")
    set(${out} "${name}" PARENT_SCOPE)
endfunction()
# The hash of a file as RECORD states it: sha256= and the SHA-256 digest in URL-safe base64
# without padding.
function(_record_hash out path)
    file(SHA256 "${path}" _hex)
    # 32 bytes and one zero byte: eleven groups of three bytes, four characters each. The last
    # character encodes only the zero byte and is dropped.
    string(APPEND _hex "00")
    set(_alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    set(_encoded "")
    foreach(_at RANGE 0 60 6)
        string(SUBSTRING "${_hex}" ${_at} 6 _group)
        math(EXPR _value "0x${_group}")
        foreach(_shift IN ITEMS 18 12 6 0)
            math(EXPR _index "(${_value} >> ${_shift}) & 63")
            string(SUBSTRING "${_alphabet}" ${_index} 1 _character)
            string(APPEND _encoded "${_character}")
        endforeach()
    endforeach()
    string(SUBSTRING "${_encoded}" 0 43 _encoded)
    set(${out} "sha256=${_encoded}" PARENT_SCOPE)
endfunction()

# ------------------------------------------------------------------------------------------------
# 1. The installed distributions: name, version, source, license and license files.
# ------------------------------------------------------------------------------------------------
# The distributions that pyproject.toml takes from a path of this checkout: their direct_url.json,
# which names the path, is removed below, so their source comes from pyproject.toml.
file(STRINGS "${PROJECT_SOURCE_DIR}/pyproject.toml" _path_sources
    REGEX "^[A-Za-z0-9_.-]+ *= *{ *path *=" ENCODING UTF-8)
set(_local_names "")
foreach(_line IN LISTS _path_sources)
    string(REGEX MATCH "^[A-Za-z0-9_.-]+" _local_name "${_line}")
    _normalize(_local_name "${_local_name}")
    list(APPEND _local_names "${_local_name}")
endforeach()

file(GLOB _dist_infos LIST_DIRECTORIES true "${SITE}/*.dist-info")
list(SORT _dist_infos)
set(_names "")
foreach(_dist_info IN LISTS _dist_infos)
    file(READ "${_dist_info}/METADATA" _metadata)
    string(FIND "${_metadata}" "\n\n" _end)
    if(_end GREATER -1)
        string(SUBSTRING "${_metadata}" 0 ${_end} _metadata)
    endif()
    string(REPLACE ";" "," _metadata "${_metadata}")
    string(REPLACE "\n" ";" _lines "${_metadata}")
    set(_name "")
    set(_version "")
    set(_license "")
    set(_license_expression "")
    set(_license_fields "")
    foreach(_line IN LISTS _lines)
        if(_line MATCHES "^Name: *(.+)$")
            set(_name "${CMAKE_MATCH_1}")
        elseif(_line MATCHES "^Version: *(.+)$")
            set(_version "${CMAKE_MATCH_1}")
        elseif(_line MATCHES "^License-Expression: *(.+)$")
            set(_license_expression "${CMAKE_MATCH_1}")
        elseif(_line MATCHES "^License: *(.+)$" AND _license STREQUAL "")
            set(_license "${CMAKE_MATCH_1}")
        elseif(_line MATCHES "^License-File: *(.+)$")
            list(APPEND _license_fields "${CMAKE_MATCH_1}")
        endif()
    endforeach()
    _normalize(_name "${_name}")
    if(NOT _license_expression STREQUAL "")
        set(_license "${_license_expression}")
    endif()
    string(LENGTH "${_license}" _length)
    if(_length GREATER 200)
        string(SUBSTRING "${_license}" 0 200 _license)
    endif()

    # License files: PEP 639's licenses/ directory, the License-File entries, or files with a
    # license's usual name in the .dist-info directory.
    set(_files "")
    if(IS_DIRECTORY "${_dist_info}/licenses")
        file(GLOB_RECURSE _found LIST_DIRECTORIES false RELATIVE "${_dist_info}"
            "${_dist_info}/licenses/*")
        list(APPEND _files ${_found})
    endif()
    foreach(_field IN LISTS _license_fields)
        if(EXISTS "${_dist_info}/${_field}" AND NOT _field IN_LIST _files)
            list(APPEND _files "${_field}")
        endif()
    endforeach()
    file(GLOB _found LIST_DIRECTORIES false RELATIVE "${_dist_info}"
        "${_dist_info}/LICENSE*" "${_dist_info}/LICENCE*" "${_dist_info}/COPYING*"
        "${_dist_info}/NOTICE*"
        "${_dist_info}/AUTHORS*")
    foreach(_file IN LISTS _found)
        if(NOT _file IN_LIST _files)
            list(APPEND _files "${_file}")
        endif()
    endforeach()
    list(SORT _files)

    # Source: a registry, a git commit, or a local directory or file of the build machine.
    set(_source "registry")
    set(_local FALSE)
    if(EXISTS "${_dist_info}/direct_url.json")
        file(READ "${_dist_info}/direct_url.json" _direct)
        string(JSON _url GET "${_direct}" url)
        string(JSON _commit ERROR_VARIABLE _no_vcs GET "${_direct}" vcs_info commit_id)
        if(NOT _no_vcs)
            set(_source "git+${_url}@${_commit}")
        elseif(_url MATCHES "^file:")
            set(_source "local")
            set(_local TRUE)
        else()
            set(_source "${_url}")
        endif()
    endif()

    if(_name IN_LIST _local_names)
        set(_source "local")
        set(_local TRUE)
    endif()

    list(APPEND _names "${_name}")
    set(_dist_${_name}_version "${_version}")
    set(_dist_${_name}_license "${_license}")
    set(_dist_${_name}_files "${_files}")
    set(_dist_${_name}_source "${_source}")
    set(_dist_${_name}_local "${_local}")
    set(_dist_${_name}_dir "${_dist_info}")
endforeach()
list(LENGTH _names _count)
message(STATUS "praenora-runtime-pyenv: ${_count} distributions installed")

# ------------------------------------------------------------------------------------------------
# 2. Checks: excluded distributions, expected versions.
# ------------------------------------------------------------------------------------------------
foreach(_excluded IN LISTS PRAENORA_PYENV_EXCLUDED_DISTRIBUTIONS)
    if(_excluded IN_LIST _names)
        message(FATAL_ERROR "The bundle holds ${_excluded}, which it must not hold "
            "(PRAENORA_PYENV_EXCLUDED_DISTRIBUTIONS, docs/upstreams.md). A change of uv.lock or "
            "pyproject.toml brought it in.")
    endif()
endforeach()
foreach(_expected IN LISTS PRAENORA_PYENV_EXPECTED_VERSIONS)
    string(REPLACE "=" ";" _expected "${_expected}")
    list(GET _expected 0 _name)
    list(GET _expected 1 _version)
    if(_name IN_LIST _names AND NOT _dist_${_name}_version STREQUAL _version)
        message(FATAL_ERROR "The bundle holds ${_name} ${_dist_${_name}_version}; "
            "PRAENORA_PYENV_EXPECTED_VERSIONS expects ${_version}. Update the expectation with "
            "the change that caused it (docs/building.md#updating-an-upstream).")
    endif()
endforeach()

# ------------------------------------------------------------------------------------------------
# 3. License files.
# ------------------------------------------------------------------------------------------------
file(REMOVE_RECURSE "${LICENSES}")
file(MAKE_DIRECTORY "${LICENSES}/praenora-runtime-pyenv")
file(COPY "${PROJECT_SOURCE_DIR}/LICENSE" DESTINATION "${LICENSES}/praenora-runtime-pyenv")
set(_source_licenses "licenses/praenora-runtime-pyenv/LICENSE")

# CPython's license, as its archive holds it.
if(EXISTS "${BUNDLE}/python/lib/python3.12/LICENSE.txt")
    set(_cpython_license "${BUNDLE}/python/lib/python3.12/LICENSE.txt")
elseif(EXISTS "${BUNDLE}/python/LICENSE.txt")
    set(_cpython_license "${BUNDLE}/python/LICENSE.txt")
else()
    message(FATAL_ERROR "CPython's LICENSE.txt is not in ${BUNDLE}/python")
endif()
file(COPY "${_cpython_license}" DESTINATION "${LICENSES}/python")
set(_python_licenses "licenses/python/LICENSE.txt")

# The upstreams that the bundle holds: inflect-sim-core always; the others with BioGears.
set(_upstreams inflect-sim-core)
if(biogears IN_LIST PRAENORA_PYENV_ENGINES_RESOLVED)
    list(APPEND _upstreams biogears pybiogears xerces-c eigen)
endif()
foreach(_upstream IN LISTS _upstreams)
    string(TOUPPER "${_upstream}" _up)
    string(REPLACE "-" "_" _up "${_up}")
    set(_upstream_${_up}_licenses "")
    foreach(_file IN LISTS PRAENORA_PYENV_${_up}_LICENSES)
        set(_path "${PROJECT_SOURCE_DIR}/${PRAENORA_PYENV_${_up}_PATH}/${_file}")
        if(NOT EXISTS "${_path}")
            message(FATAL_ERROR "The license file ${_file} of ${_upstream} does not exist "
                "(PRAENORA_PYENV_${_up}_LICENSES in cmake/PraenoraPyenvVersions.cmake).")
        endif()
        get_filename_component(_directory "${LICENSES}/${_upstream}/${_file}" DIRECTORY)
        file(COPY "${_path}" DESTINATION "${_directory}")
        list(APPEND _upstream_${_up}_licenses "licenses/${_upstream}/${_file}")
    endforeach()
endforeach()

# Each distribution's license files, under licenses/python-packages/<name>/.
foreach(_name IN LISTS _names)
    set(_dist_${_name}_bundle_files "")
    foreach(_file IN LISTS _dist_${_name}_files)
        set(_target "${LICENSES}/python-packages/${_name}/${_file}")
        get_filename_component(_directory "${_target}" DIRECTORY)
        file(COPY "${_dist_${_name}_dir}/${_file}" DESTINATION "${_directory}")
        list(APPEND _dist_${_name}_bundle_files "licenses/python-packages/${_name}/${_file}")
    endforeach()
    if(NOT _dist_${_name}_files)
        set(_allowed FALSE)
        foreach(_entry IN LISTS PRAENORA_PYENV_LICENSE_ALLOWLIST)
            if(_entry MATCHES "^${_name}=")
                set(_allowed TRUE)
            endif()
        endforeach()
        if(NOT _allowed)
            message(FATAL_ERROR "${_name} ${_dist_${_name}_version} ships no license file "
                "(its metadata says: '${_dist_${_name}_license}'). Add it to "
                "PRAENORA_PYENV_LICENSE_ALLOWLIST with its license, after checking it "
                "(docs/outputs.md#licenses).")
        endif()
    endif()
endforeach()

# ------------------------------------------------------------------------------------------------
# 4. Relocation: nothing that the interpreter, a console script or the CMake package reads names
#    this build machine's paths.
# ------------------------------------------------------------------------------------------------
# Metadata files of local sources (their direct_url.json names the checkout) and of uv's build
# cache, each with its line in RECORD.
foreach(_name IN LISTS _names)
    set(_dist_info "${_dist_${_name}_dir}")
    get_filename_component(_dist_info_name "${_dist_info}" NAME)
    set(_remove "")
    if(_dist_${_name}_local)
        list(APPEND _remove direct_url.json)
    endif()
    foreach(_file IN ITEMS uv_build.json uv_cache.json)
        if(EXISTS "${_dist_info}/${_file}")
            list(APPEND _remove "${_file}")
        endif()
    endforeach()
    if(_remove)
        file(STRINGS "${_dist_info}/RECORD" _record)
        foreach(_file IN LISTS _remove)
            file(REMOVE "${_dist_info}/${_file}")
            list(FILTER _record EXCLUDE REGEX "^${_dist_info_name}/${_file},")
        endforeach()
        list(JOIN _record "\n" _record)
        file(WRITE "${_dist_info}/RECORD" "${_record}\n")
    endif()
endforeach()

# Software bills of materials (.dist-info/sboms/) of distributions built here name their source
# checkout in uv's cache by its absolute path: maturin's of viva-core lists its Rust packages by
# cargo package IDs such as path+file:///<uv cache>/git-v0/checkouts/<id>/<commit>/crates/<name>.
# The path of uv's cache, without a leading /, becomes uv-cache, so that such an ID reads
# path+file:///uv-cache/... on every build machine; the file's line in RECORD gets its new hash
# and size.
get_filename_component(_cache_real "${PRAENORA_PYENV_UV_CACHE_DIR}" REALPATH)
set(_cache_paths "")
foreach(_path IN ITEMS "${PRAENORA_PYENV_UV_CACHE_DIR}" "${_cache_real}")
    string(REGEX REPLACE "^/" "" _path "${_path}")
    if(NOT _path STREQUAL "" AND NOT _path IN_LIST _cache_paths)
        list(APPEND _cache_paths "${_path}")
    endif()
endforeach()
foreach(_name IN LISTS _names)
    set(_dist_info "${_dist_${_name}_dir}")
    file(GLOB_RECURSE _sboms LIST_DIRECTORIES false "${_dist_info}/sboms/*")
    set(_record "")
    set(_rewritten FALSE)
    foreach(_sbom IN LISTS _sboms)
        file(READ "${_sbom}" _text)
        set(_new "${_text}")
        foreach(_path IN LISTS _cache_paths)
            string(REPLACE "${_path}" "uv-cache" _new "${_new}")
        endforeach()
        if(_new STREQUAL _text)
            continue()
        endif()
        file(WRITE "${_sbom}" "${_new}")
        if(NOT _rewritten)
            file(STRINGS "${_dist_info}/RECORD" _record)
            set(_rewritten TRUE)
        endif()
        file(RELATIVE_PATH _relative "${SITE}" "${_sbom}")
        _record_hash(_hash "${_sbom}")
        file(SIZE "${_sbom}" _size)
        set(_updated "")
        foreach(_line IN LISTS _record)
            string(FIND "${_line}" "${_relative}," _at)
            if(_at EQUAL 0)
                set(_line "${_relative},${_hash},${_size}")
            endif()
            list(APPEND _updated "${_line}")
        endforeach()
        set(_record "${_updated}")
    endforeach()
    if(_rewritten)
        list(JOIN _record "\n" _record)
        file(WRITE "${_dist_info}/RECORD" "${_record}\n")
    endif()
endforeach()

# Bytecode that a process wrote into site-packages after the installation (the installation
# compiles none): it names the paths of the machine that wrote it.
file(GLOB_RECURSE _bytecode LIST_DIRECTORIES true "${SITE}/*")
list(FILTER _bytecode INCLUDE REGEX "/__pycache__$")
foreach(_directory IN LISTS _bytecode)
    if(IS_DIRECTORY "${_directory}")
        file(REMOVE_RECURSE "${_directory}")
    endif()
endforeach()

if(PRAENORA_PYENV_OS STREQUAL "windows")
    # Console-script launchers (.exe) name the interpreter's absolute path; consumers run
    # python -m <module> instead (not yet verified).
    file(GLOB _launchers LIST_DIRECTORIES false "${BUNDLE}/python/Scripts/*.exe")
    foreach(_launcher IN LISTS _launchers)
        file(TO_NATIVE_PATH "${BUNDLE}" _native_bundle)
        file(READ "${_launcher}" _content HEX)
        string(HEX "${_native_bundle}" _bundle_hex)
        string(TOLOWER "${_bundle_hex}" _bundle_hex)
        string(FIND "${_content}" "${_bundle_hex}" _at)
        if(_at GREATER -1)
            file(REMOVE "${_launcher}")
        endif()
    endforeach()
else()
    # Console scripts: uv writes the interpreter's absolute path; the form that
    # python-build-standalone's own scripts use finds the interpreter beside the script.
    file(GLOB _scripts LIST_DIRECTORIES false "${BUNDLE}/python/bin/*")
    set(_relative_exec "'''exec' \"$(dirname -- \"$(realpath -- \"$0\")\")/python3.12\"")
    string(APPEND _relative_exec " \"$0\" \"$@\"")
    foreach(_script IN LISTS _scripts)
        if(IS_SYMLINK "${_script}")
            continue()
        endif()
        file(READ "${_script}" _head LIMIT 512)
        if(NOT _head MATCHES "^#!")
            continue()
        endif()
        file(READ "${_script}" _text)
        string(FIND "${_text}" "\n" _first_end)
        string(SUBSTRING "${_text}" 0 ${_first_end} _first)
        math(EXPR _rest_start "${_first_end} + 1")
        string(SUBSTRING "${_text}" ${_rest_start} -1 _rest)
        set(_new "")
        if(_first MATCHES "^#!${BUNDLE}/python/bin/python")
            # #!/abs/python3 -> the two-line form
            set(_new "#!/bin/sh\n${_relative_exec}\n' '''\n${_rest}")
        elseif(_first STREQUAL "#!/bin/sh" AND _rest MATCHES "^'''exec' '${BUNDLE}/python/bin/")
            string(FIND "${_rest}" "\n" _second_end)
            math(EXPR _after "${_second_end} + 1")
            string(SUBSTRING "${_rest}" ${_after} -1 _tail)
            set(_new "#!/bin/sh\n${_relative_exec}\n${_tail}")
        endif()
        if(NOT _new STREQUAL "")
            file(WRITE "${_script}" "${_new}")
        endif()
    endforeach()

    # python3.12-config, which FindPython runs to find libpython, is CPython's shell script on
    # Linux (Misc/python-config.sh.in; macOS has its Python form). It derives its prefix from its
    # own path with unquoted command substitutions: under a path with a space, the prefix is empty
    # and FindPython takes the libpython of /lib. The two lines get quotes.
    set(_config "${BUNDLE}/python/bin/python3.12-config")
    set(_unquoted [=[RESULT=$(dirname $(cd $(dirname "$1") && pwd -P))]=]
        [=[echo $RESULT]=])
    set(_quoted [=[RESULT=$(dirname "$(cd "$(dirname "$1")" && pwd -P)")]=]
        [=[echo "$RESULT"]=])
    if(EXISTS "${_config}" AND NOT IS_SYMLINK "${_config}")
        file(READ "${_config}" _text)
        string(FIND "${_text}" "installed_prefix ()" _shell)
        if(_shell GREATER -1)
            set(_new "${_text}")
            foreach(_index RANGE 1)
                list(GET _unquoted ${_index} _from)
                list(GET _quoted ${_index} _to)
                string(REPLACE "${_from}" "${_to}" _new "${_new}")
                string(FIND "${_new}" "${_to}" _at)
                if(_at EQUAL -1)
                    message(FATAL_ERROR "${_config} does not contain '${_from}': quote its "
                        "installed_prefix function in another way.")
                endif()
            endforeach()
            if(NOT _new STREQUAL _text)
                file(WRITE "${_config}" "${_new}")
            endif()
        endif()
    endif()
endif()

# pybiogears' extension module names BioGears' library directory in the build tree; it gets a
# load path relative to itself to <bundle>/biogears/lib.
if(biogears IN_LIST PRAENORA_PYENV_ENGINES_RESOLVED)
    file(GLOB _extensions LIST_DIRECTORIES false "${SITE}/pybiogears/*.so")
    if(NOT _extensions)
        message(FATAL_ERROR "pybiogears' extension module is not in ${SITE}/pybiogears")
    endif()
    file(RELATIVE_PATH _to_lib "${SITE}/pybiogears" "${BUNDLE}/${PRAENORA_PYENV_BIOGEARS_LIB_REL}")
    foreach(_extension IN LISTS _extensions)
        if(PRAENORA_PYENV_OS STREQUAL "macos")
            execute_process(COMMAND otool -l "${_extension}" OUTPUT_VARIABLE _output
                ENCODING UTF-8)
            string(REGEX MATCHALL "cmd LC_RPATH\n[^\n]*\n *path ([^\n]*) \\(offset" _rpaths
                "${_output}")
            foreach(_entry IN LISTS _rpaths)
                string(REGEX REPLACE ".* path (.*) \\(offset" "\\1" _rpath "${_entry}")
                _run(install_name_tool -delete_rpath "${_rpath}" "${_extension}")
            endforeach()
            _run(install_name_tool -add_rpath "@loader_path/${_to_lib}" "${_extension}")
            _run(codesign --force --sign - "${_extension}")
        else()
            find_program(_patchelf patchelf)
            if(NOT _patchelf)
                message(FATAL_ERROR "patchelf is needed to make pybiogears relocatable "
                    "(docs/building.md#requirements).")
            endif()
            _run("${_patchelf}" --set-rpath "$ORIGIN/${_to_lib}" "${_extension}")
        endif()
    endforeach()
endif()

# ------------------------------------------------------------------------------------------------
# 5. The oldest macOS that every binary of the bundle runs on: the highest minimum version that a
#    Mach-O file names.
# ------------------------------------------------------------------------------------------------
set(PRAENORA_PYENV_OS_MIN_VERSION_MEASURED "")
if(PRAENORA_PYENV_OS STREQUAL "macos")
    file(GLOB_RECURSE _binaries LIST_DIRECTORIES false
        "${BUNDLE}/*.so" "${BUNDLE}/*.dylib" "${BUNDLE}/python/bin/python3.12")
    set(_highest "0")
    foreach(_binary IN LISTS _binaries)
        if(IS_SYMLINK "${_binary}")
            continue()
        endif()
        set(_ignored FALSE)
        foreach(_pattern IN LISTS PRAENORA_PYENV_OS_MIN_VERSION_IGNORE)
            if(_binary MATCHES "${_pattern}")
                set(_ignored TRUE)
            endif()
        endforeach()
        if(_ignored)
            continue()
        endif()
        execute_process(COMMAND otool -l "${_binary}" OUTPUT_VARIABLE _output
            ERROR_QUIET ENCODING UTF-8)
        string(REGEX MATCHALL "minos [0-9.]+|LC_VERSION_MIN_MACOSX\n[^\n]*\n *version [0-9.]+"
            _versions "${_output}")
        foreach(_version IN LISTS _versions)
            string(REGEX MATCH "[0-9.]+$" _version "${_version}")
            if(_version VERSION_GREATER _highest)
                set(_highest "${_version}")
            endif()
        endforeach()
    endforeach()
    set(PRAENORA_PYENV_OS_MIN_VERSION_MEASURED "${_highest}")
    message(STATUS "praenora-runtime-pyenv: the bundle's binaries need macOS ${_highest} or later")
endif()

# ------------------------------------------------------------------------------------------------
# 6. The manifest.
# ------------------------------------------------------------------------------------------------
execute_process(COMMAND git -C "${PROJECT_SOURCE_DIR}" rev-parse HEAD
    RESULT_VARIABLE _result OUTPUT_VARIABLE _commit OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET ENCODING UTF-8)
set(_modified "null")
if(_result EQUAL 0)
    execute_process(COMMAND git -C "${PROJECT_SOURCE_DIR}" status --porcelain
        --untracked-files=no --ignore-submodules=all
        OUTPUT_VARIABLE _status OUTPUT_STRIP_TRAILING_WHITESPACE ENCODING UTF-8)
    if(_status STREQUAL "")
        set(_modified "false")
    else()
        set(_modified "true")
    endif()
else()
    set(_commit "")
endif()
file(SHA256 "${PROJECT_SOURCE_DIR}/uv.lock" _lock_sha256)

macro(_set member value)
    string(JSON _manifest SET "${_manifest}" ${member} "${value}")
endmacro()
set(_manifest "{}")
_set(manifest_version "${PRAENORA_PYENV_MANIFEST_VERSION}")
_json_string(_v "praenora-runtime-pyenv")
_set(name "${_v}")
_json_string(_v "${PROJECT_VERSION}")
_set(version "${_v}")
_json_string(_v "${PRAENORA_PYENV_PACKAGE_NAME}")
_set(package "${_v}")

_json_string(_repository "${PROJECT_HOMEPAGE_URL}")
_json_nullable(_commit_json "${_commit}")
_json_array(_licenses_json ${_source_licenses})
_set(source "{\"repository\": ${_repository}, \"commit\": ${_commit_json}, \
\"modified\": ${_modified}, \"licenses\": ${_licenses_json}}")

_json_string(_os "${PRAENORA_PYENV_OS}")
_json_string(_arch "${PRAENORA_PYENV_ARCH}")
_json_nullable(_min "${PRAENORA_PYENV_OS_MIN_VERSION_MEASURED}")
_json_nullable(_distribution "${PRAENORA_PYENV_DISTRIBUTION}")
_set(platform "{\"os\": ${_os}, \"arch\": ${_arch}, \"os_min_version\": ${_min}, \
\"distribution\": ${_distribution}}")

_json_string(_id "${PRAENORA_PYENV_COMPILER_ID}")
_json_string(_version "${PRAENORA_PYENV_COMPILER_VERSION}")
_json_string(_label "${PRAENORA_PYENV_COMPILER_LABEL}")
_json_string(_stdlib "${PRAENORA_PYENV_CXX_STDLIB}")
_json_nullable(_runtime "${PRAENORA_PYENV_MSVC_RUNTIME}")
_set(compiler "{\"id\": ${_id}, \"version\": ${_version}, \"label\": ${_label}, \
\"cxx_stdlib\": ${_stdlib}, \"msvc_runtime\": ${_runtime}}")
_set(build_type "\"Release\"")

set(_python "{}")
foreach(_pair IN ITEMS "version=${PRAENORA_PYENV_PYTHON_VERSION}"
                       "abi=${PRAENORA_PYENV_PYTHON_ABI}"
                       "implementation=cpython"
                       "release=${PRAENORA_PYENV_PYTHON_RELEASE}"
                       "archive=${PRAENORA_PYENV_PYTHON_ARCHIVE}"
                       "sha256=${PRAENORA_PYENV_PYTHON_SHA256}"
                       "home=${PRAENORA_PYENV_PYTHON_HOME_REL}"
                       "executable=${PRAENORA_PYENV_PYTHON_EXECUTABLE_REL}"
                       "library=${PRAENORA_PYENV_PYTHON_LIBRARY_REL}"
                       "include_dir=${PRAENORA_PYENV_PYTHON_INCLUDE_DIR_REL}"
                       "site_packages=${PRAENORA_PYENV_PYTHON_SITE_PACKAGES_REL}")
    string(FIND "${_pair}" "=" _at)
    string(SUBSTRING "${_pair}" 0 ${_at} _key)
    math(EXPR _at "${_at} + 1")
    string(SUBSTRING "${_pair}" ${_at} -1 _value)
    _json_string(_value "${_value}")
    string(JSON _python SET "${_python}" ${_key} "${_value}")
endforeach()
_json_array(_python_licenses_json ${_python_licenses})
string(JSON _python SET "${_python}" licenses "${_python_licenses_json}")
_set(python "${_python}")

_json_string(_uv "${PRAENORA_PYENV_UV_VERSION}")
_json_nullable(_rust "${PRAENORA_PYENV_RUST_VERSION}")
_json_nullable(_xsd "${PRAENORA_PYENV_XSD_VERSION}")
_set(tools "{\"uv\": ${_uv}, \"rust\": ${_rust}, \"xsd\": ${_xsd}}")
_json_string(_v "${_lock_sha256}")
_set(lock "{\"sha256\": ${_v}}")

set(_upstreams_json "{}")
foreach(_upstream IN LISTS _upstreams)
    string(TOUPPER "${_upstream}" _up)
    string(REPLACE "-" "_" _up "${_up}")
    # The version: the installed distribution's for the Python upstreams, else the release tag.
    if(_upstream STREQUAL "inflect-sim-core")
        set(_version "${_dist_simulation-core_version}")
    elseif(_upstream STREQUAL "pybiogears")
        set(_version "${_dist_pybiogears_version}")
    else()
        string(REGEX REPLACE "^v" "" _version "${PRAENORA_PYENV_${_up}_REF}")
    endif()
    _json_string(_repository "${PRAENORA_PYENV_${_up}_REPOSITORY}")
    _json_string(_ref "${PRAENORA_PYENV_${_up}_REF}")
    _json_string(_commit "${PRAENORA_PYENV_${_up}_COMMIT}")
    _json_nullable(_version "${_version}")
    _json_array(_files ${_upstream_${_up}_licenses})
    if(PRAENORA_PYENV_${_up}_MODIFIED)
        set(_upstream_modified true)
    else()
        set(_upstream_modified false)
    endif()
    string(JSON _upstreams_json SET "${_upstreams_json}" ${_upstream} "{\"repository\": \
${_repository}, \"ref\": ${_ref}, \"commit\": ${_commit}, \"modified\": ${_upstream_modified}, \
\"version\": ${_version}, \"licenses\": ${_files}}")
endforeach()
_set(upstreams "${_upstreams_json}")

set(_engines_json "{}")
foreach(_engine IN LISTS PRAENORA_PYENV_ENGINES_RESOLVED)
    string(TOUPPER "${_engine}" _up)
    set(_distribution "${PRAENORA_PYENV_ENGINE_${_up}_DISTRIBUTION}")
    _json_string(_distribution_json "${_distribution}")
    _json_nullable(_version "${_dist_${_distribution}_version}")
    set(_entry "{\"distribution\": ${_distribution_json}, \"version\": ${_version}}")
    if(_engine STREQUAL "biogears")
        _json_string(_runtime_dir "${PRAENORA_PYENV_BIOGEARS_RUNTIME_REL}")
        string(JSON _entry SET "${_entry}" runtime_dir "${_runtime_dir}")
    endif()
    string(JSON _engines_json SET "${_engines_json}" ${_engine} "${_entry}")
endforeach()
_set(engines "${_engines_json}")

set(_distributions "")
foreach(_name IN LISTS _names)
    _json_string(_name_json "${_name}")
    _json_string(_version "${_dist_${_name}_version}")
    _json_string(_source "${_dist_${_name}_source}")
    _json_nullable(_license "${_dist_${_name}_license}")
    _json_array(_files ${_dist_${_name}_bundle_files})
    list(APPEND _distributions "{\"name\": ${_name_json}, \"version\": ${_version}, \
\"source\": ${_source}, \"license\": ${_license}, \"license_files\": ${_files}}")
endforeach()
list(JOIN _distributions ", " _distributions)
_set(distributions "[${_distributions}]")
_json_array(_excluded ${PRAENORA_PYENV_EXCLUDED_DISTRIBUTIONS})
_set(excluded "${_excluded}")

# The environment of a process that runs the bundle's Python: paths relative to the bundle, and
# values.
set(_paths "{\"PYTHONHOME\": \"${PRAENORA_PYENV_PYTHON_HOME_REL}\"}")
if(biogears IN_LIST PRAENORA_PYENV_ENGINES_RESOLVED)
    string(JSON _paths SET "${_paths}" BIOGEARS_RUNTIME
        "\"${PRAENORA_PYENV_BIOGEARS_RUNTIME_REL}\"")
endif()
# An empty PYTHONPATH counts as unset, and PYTHONSAFEPATH keeps the current directory and the
# script's directory off sys.path, so a caller's environment cannot shadow the bundle's modules.
_set(environment "{\"paths\": ${_paths}, \"values\": {\"PYTHONNOUSERSITE\": \"1\", \
\"PYTHONDONTWRITEBYTECODE\": \"1\", \"PYTHONPATH\": \"\", \"PYTHONSAFEPATH\": \"1\"}}")
_set(consumer "{\"python_root_dir\": \"${PRAENORA_PYENV_PYTHON_HOME_REL}\", \
\"cmake_package_dir\": \"lib/cmake/PraenoraRuntimePyenv\"}")

file(WRITE "${BUNDLE}/praenora-runtime-pyenv.json" "${_manifest}\n")

# ------------------------------------------------------------------------------------------------
# 7. The CMake package.
# ------------------------------------------------------------------------------------------------
set(PRAENORA_PYENV_HOMEPAGE "${PROJECT_HOMEPAGE_URL}")
set(_package "${BUNDLE}/lib/cmake/PraenoraRuntimePyenv")
file(REMOVE_RECURSE "${_package}")
configure_file("${PROJECT_SOURCE_DIR}/cmake/PraenoraRuntimePyenvConfig.cmake.in"
    "${_package}/PraenoraRuntimePyenvConfig.cmake" @ONLY)
configure_file("${PROJECT_SOURCE_DIR}/cmake/PraenoraRuntimePyenvConfigVersion.cmake.in"
    "${_package}/PraenoraRuntimePyenvConfigVersion.cmake" @ONLY)

message(STATUS "praenora-runtime-pyenv: bundle ${PRAENORA_PYENV_PACKAGE_NAME} written to ${BUNDLE}")
