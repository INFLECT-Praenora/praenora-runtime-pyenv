# Completes BioGears' installation in the build tree and copies what the bundle needs of BioGears
# and Xerces-C at run time into it, as pybiogears' scripts/install_biogears.sh does for its own
# installations. Script mode, run by the target pyenv_biogears_bundle
# (cmake/PraenoraPyenvNative.cmake):
#
#   cmake -DBIOGEARS_SOURCE=<dir> -DBIOGEARS_PREFIX=<dir> -DXERCES_PREFIX=<dir> -DBUILD_DIR=<dir>
#         -DLIB_DIR=<dir> -DRUNTIME_DIR=<dir> -P cmake/praenora_pyenv_biogears_bundle.cmake
#
# 1. BioGears 8.2.0's installation omits its XSD-generated headers (biogears/schema/...), which its
#    public headers include; they are copied from its build tree when missing.
# 2. LIB_DIR receives BioGears' and Xerces-C's shared libraries. On macOS, BioGears' installed
#    libraries keep build-tree load paths (its INSTALL_RPATH is malformed); each copy gets the
#    install name @rpath/<file>, refers to the others by @rpath and has the one rpath
#    @loader_path, and is signed again (arm64 loads no binary whose signature is invalid). On
#    Linux, each copy gets the RUNPATH $ORIGIN with patchelf (not yet verified).
# 3. RUNTIME_DIR receives BioGears' data directory, the directory that BIOGEARS_RUNTIME names.

cmake_minimum_required(VERSION 3.24)

foreach(_variable IN ITEMS BIOGEARS_SOURCE BIOGEARS_PREFIX XERCES_PREFIX BUILD_DIR LIB_DIR
                           RUNTIME_DIR)
    if(NOT DEFINED ${_variable} OR "${${_variable}}" STREQUAL "")
        message(FATAL_ERROR "praenora_pyenv_biogears_bundle.cmake: ${_variable} is not set")
    endif()
endforeach()

function(_run)
    execute_process(COMMAND ${ARGN} RESULT_VARIABLE _result OUTPUT_VARIABLE _output
        ERROR_VARIABLE _output ENCODING UTF-8)
    if(NOT _result EQUAL 0)
        list(JOIN ARGN " " _command)
        message(FATAL_ERROR "${_command} failed: ${_output}")
    endif()
endfunction()

# 1. The generated schema headers.
set(_schema "${BIOGEARS_PREFIX}/include/biogears/schema")
if(NOT EXISTS "${_schema}/cdm/Circuit.hxx")
    set(_generated "")
    foreach(_candidate IN ITEMS
            "${BUILD_DIR}/biogears/build/projects/biogears/generated/Release/biogears/schema"
            "${BUILD_DIR}/biogears/build/projects/biogears/generated/biogears/schema")
        if(EXISTS "${_candidate}/cdm/Circuit.hxx")
            set(_generated "${_candidate}")
            break()
        endif()
    endforeach()
    if(_generated STREQUAL "")
        message(FATAL_ERROR "BioGears' generated schema headers were not found below "
            "${BUILD_DIR}/biogears/build/projects/biogears/generated")
    endif()
    file(REMOVE_RECURSE "${_schema}")
    file(COPY "${_generated}/" DESTINATION "${_schema}")
endif()

# 2. The shared libraries, with their symbolic links.
file(REMOVE_RECURSE "${LIB_DIR}")
file(MAKE_DIRECTORY "${LIB_DIR}")
if(APPLE)
    set(_patterns "${BIOGEARS_PREFIX}/lib/libbiogears*.dylib"
                  "${XERCES_PREFIX}/lib/libxerces-c*.dylib")
else()
    set(_patterns "${BIOGEARS_PREFIX}/lib/libbiogears*.so*"
                  "${XERCES_PREFIX}/lib/libxerces-c*.so*")
endif()
file(GLOB _libraries LIST_DIRECTORIES false ${_patterns})
if(NOT _libraries)
    message(FATAL_ERROR "No shared libraries match ${_patterns}")
endif()
file(COPY ${_libraries} DESTINATION "${LIB_DIR}" USE_SOURCE_PERMISSIONS)
file(GLOB _copies LIST_DIRECTORIES false "${LIB_DIR}/*")

foreach(_library IN LISTS _copies)
    if(IS_SYMLINK "${_library}")
        continue()
    endif()
    get_filename_component(_name "${_library}" NAME)
    if(APPLE)
        execute_process(COMMAND otool -L "${_library}" OUTPUT_VARIABLE _output ENCODING UTF-8)
        string(REPLACE "\n" ";" _lines "${_output}")
        list(REMOVE_AT _lines 0)
        foreach(_line IN LISTS _lines)
            string(STRIP "${_line}" _line)
            if(NOT _line MATCHES "^([^ ]+) \\(")
                continue()
            endif()
            set(_dependency "${CMAKE_MATCH_1}")
            get_filename_component(_dependency_name "${_dependency}" NAME)
            if(NOT _dependency MATCHES "^@" AND
               (_dependency_name MATCHES "^lib(biogears|xerces-c)" OR
                _dependency MATCHES "^${BUILD_DIR}"))
                _run(install_name_tool -change "${_dependency}" "@rpath/${_dependency_name}"
                     "${_library}")
            endif()
        endforeach()
        _run(install_name_tool -id "@rpath/${_name}" "${_library}")
        execute_process(COMMAND otool -l "${_library}" OUTPUT_VARIABLE _output ENCODING UTF-8)
        string(REGEX MATCHALL "cmd LC_RPATH\n[^\n]*\n *path ([^\n]*) \\(offset" _rpaths
            "${_output}")
        foreach(_entry IN LISTS _rpaths)
            string(REGEX REPLACE ".* path (.*) \\(offset" "\\1" _rpath "${_entry}")
            _run(install_name_tool -delete_rpath "${_rpath}" "${_library}")
        endforeach()
        _run(install_name_tool -add_rpath "@loader_path" "${_library}")
        _run(codesign --force --sign - "${_library}")
    else()
        find_program(_patchelf patchelf)
        if(NOT _patchelf)
            message(FATAL_ERROR "patchelf is needed to make BioGears' libraries relocatable "
                "(docs/building.md#requirements).")
        endif()
        _run("${_patchelf}" --set-rpath "$ORIGIN" "${_library}")
    endif()
endforeach()

# 3. The data directory.
file(REMOVE_RECURSE "${RUNTIME_DIR}")
file(MAKE_DIRECTORY "${RUNTIME_DIR}")
file(COPY "${BIOGEARS_SOURCE}/share/data/" DESTINATION "${RUNTIME_DIR}")
file(COPY "${BIOGEARS_SOURCE}/share/xsd" DESTINATION "${RUNTIME_DIR}")
file(COPY "${BIOGEARS_SOURCE}/share/Scenarios" DESTINATION "${RUNTIME_DIR}")
file(COPY "${BIOGEARS_SOURCE}/share/etc/UCEDefs.conf" DESTINATION "${RUNTIME_DIR}")
if(NOT EXISTS "${RUNTIME_DIR}/states/StandardMale@0s.xml")
    message(FATAL_ERROR "${RUNTIME_DIR} holds no states/StandardMale@0s.xml")
endif()
