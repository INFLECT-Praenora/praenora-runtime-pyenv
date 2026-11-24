# The native build of the biogears engine: Eigen, Xerces-C and BioGears 8.2.0, each an external
# project built from its submodule into a work prefix in the build tree, against which uv then
# builds pybiogears. A script (cmake/praenora_pyenv_biogears_bundle.cmake) copies what the bundle
# needs at run time into <bundle>/biogears: BioGears' and Xerces-C's shared libraries, with load
# paths relative to themselves, and BioGears' data directory (docs/building.md).
#
# Defines, when biogears is among the engines:
#   targets pyenv_eigen, pyenv_xerces_c, pyenv_biogears, pyenv_biogears_bundle
#   PRAENORA_PYENV_BIOGEARS_PREFIX       BioGears' installation in the build tree (pybiogears is
#                                        built against it)
#   PRAENORA_PYENV_BIOGEARS_DEPENDENCIES <name>=<value> definitions of cache variables that name
#                                        Eigen, Xerces-C and CodeSynthesis XSD for BioGears' CMake
#                                        modules, for BioGears' build and pybiogears' alike
#   PRAENORA_PYENV_BIOGEARS_LIB_REL      <bundle>/biogears/lib, relative to the bundle
#   PRAENORA_PYENV_BIOGEARS_RUNTIME_REL  BioGears' data directory (BIOGEARS_RUNTIME), relative to
#                                        the bundle

include_guard(GLOBAL)
include(ExternalProject)

set(PRAENORA_PYENV_BIOGEARS_LIB_REL "biogears/lib")
set(PRAENORA_PYENV_BIOGEARS_RUNTIME_REL "biogears/share/biogears/runtime")

set(_praenora_pyenv_work "${PROJECT_BINARY_DIR}/work")
set(_praenora_pyenv_eigen_prefix "${_praenora_pyenv_work}/eigen/install")
set(_praenora_pyenv_xerces_prefix "${_praenora_pyenv_work}/xerces-c/install")
set(PRAENORA_PYENV_BIOGEARS_PREFIX "${_praenora_pyenv_work}/biogears/install")

# The Eigen, Xerces-C and XSD that BioGears' CMake modules (FindXerces-c.cmake,
# FindCodeSynthesis.cmake, BiogearsConfig.cmake) use, named explicitly instead of searched for.
# FindXerces-c.cmake looks for the library name xerces-c-3.2 before xerces-c, so a search finds a
# libxerces-c-3.2.so of the system (Ubuntu's xsdcxx package installs one) before the Xerces-C of
# the work prefix, and pybiogears' build would find Homebrew's Xerces-C on macOS.
set(_praenora_pyenv_xerces_library
    "${_praenora_pyenv_xerces_prefix}/lib/${CMAKE_SHARED_LIBRARY_PREFIX}xerces-c\
${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(PRAENORA_PYENV_BIOGEARS_DEPENDENCIES
    "Eigen3_DIR=${_praenora_pyenv_eigen_prefix}/share/eigen3/cmake"
    "Xerces-c_INCLUDE_DIR=${_praenora_pyenv_xerces_prefix}/include"
    "Xerces-c_LIBRARY_RELEASE_DYNAMIC=${_praenora_pyenv_xerces_library}"
    "Xerces-c_LIBRARY_DEBUG_DYNAMIC=${_praenora_pyenv_xerces_library}"
    "CodeSynthesis_EXECUTABLE=${PRAENORA_PYENV_XSD_EXECUTABLE}"
    "CodeSynthesis_INCLUDE_DIR=${PRAENORA_PYENV_XSD_INCLUDE_DIR}")

# What every external project gets: the project's compilers, build type, architecture, macOS
# deployment target, position-independent code and lib as library directory. CMake's package
# registries are neither searched nor written: packages registered on the build machine are not
# found, and Eigen's export(PACKAGE) does not register its build tree for the user.
set(_praenora_pyenv_common_args
    "-DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}"
    "-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}"
    "-DCMAKE_BUILD_TYPE=Release"
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DCMAKE_INSTALL_LIBDIR=lib
    -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF
    -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF
    -DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON
    -DCMAKE_INSTALL_MESSAGE=LAZY
    -G Ninja)
if(APPLE)
    list(APPEND _praenora_pyenv_common_args
        "-DCMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}"
        "-DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}")
endif()
foreach(_praenora_pyenv_launcher IN ITEMS C CXX)
    if(CMAKE_${_praenora_pyenv_launcher}_COMPILER_LAUNCHER)
        list(APPEND _praenora_pyenv_common_args
            "-DCMAKE_${_praenora_pyenv_launcher}_COMPILER_LAUNCHER=\
${CMAKE_${_praenora_pyenv_launcher}_COMPILER_LAUNCHER}")
    endif()
endforeach()

# Eigen, header-only: BioGears compiles it in; the bundle does not hold it.
ExternalProject_Add(pyenv_eigen
    SOURCE_DIR "${PROJECT_SOURCE_DIR}/${PRAENORA_PYENV_EIGEN_PATH}"
    BINARY_DIR "${_praenora_pyenv_work}/eigen/build"
    INSTALL_DIR "${_praenora_pyenv_eigen_prefix}"
    CMAKE_ARGS ${_praenora_pyenv_common_args}
        "-DCMAKE_INSTALL_PREFIX=${_praenora_pyenv_eigen_prefix}"
        -DBUILD_TESTING=OFF
        -DEIGEN_BUILD_DOC=OFF
        -DEIGEN_BUILD_PKGCONFIG=OFF
    BUILD_COMMAND ""
    DOWNLOAD_COMMAND ""
    UPDATE_COMMAND ""
    USES_TERMINAL_CONFIGURE ON
    USES_TERMINAL_INSTALL ON)

# Xerces-C, a shared library that BioGears loads at run time. No network access (it would need
# curl) and no ICU, so that it depends on the system's libraries only and uses the platform's own
# transcoder.
ExternalProject_Add(pyenv_xerces_c
    SOURCE_DIR "${PROJECT_SOURCE_DIR}/${PRAENORA_PYENV_XERCES_C_PATH}"
    BINARY_DIR "${_praenora_pyenv_work}/xerces-c/build"
    INSTALL_DIR "${_praenora_pyenv_xerces_prefix}"
    CMAKE_ARGS ${_praenora_pyenv_common_args}
        "-DCMAKE_INSTALL_PREFIX=${_praenora_pyenv_xerces_prefix}"
        -DBUILD_SHARED_LIBS=ON
        -Dnetwork=OFF
        -DCMAKE_DISABLE_FIND_PACKAGE_ICU=ON
        -DCMAKE_DISABLE_FIND_PACKAGE_CURL=ON
    DOWNLOAD_COMMAND ""
    UPDATE_COMMAND ""
    USES_TERMINAL_CONFIGURE ON
    USES_TERMINAL_BUILD ON
    USES_TERMINAL_INSTALL ON)

# BioGears, with the options of pybiogears' scripts/install_biogears.sh: its library and data
# only, without how-to examples, tests, command-line tools or website.
set(_praenora_pyenv_biogears_args
    "-DCMAKE_INSTALL_PREFIX=${PRAENORA_PYENV_BIOGEARS_PREFIX}"
    "-DCMAKE_PREFIX_PATH=${_praenora_pyenv_xerces_prefix}|${_praenora_pyenv_eigen_prefix}")
foreach(_praenora_pyenv_definition IN LISTS PRAENORA_PYENV_BIOGEARS_DEPENDENCIES)
    list(APPEND _praenora_pyenv_biogears_args "-D${_praenora_pyenv_definition}")
endforeach()
list(APPEND _praenora_pyenv_biogears_args
    -DBiogears_BUILD_HOWTOS=OFF
    -DBiogears_BUILD_TEST=OFF
    -DBiogears_BUILD_TOOLS=OFF
    -DBiogears_BUILD_WEBSITE=OFF
    # Boost only serves the command-line tools, which are not built.
    -DCMAKE_DISABLE_FIND_PACKAGE_Boost=ON
    -DCMAKE_DISABLE_FIND_PACKAGE_GTest=ON)
if(APPLE)
    # BioGears bundles zlib 1.2.11, whose zutil.h defines fdopen as NULL when TARGET_OS_MAC is
    # defined, which recent macOS SDKs do; the definition then breaks <stdio.h>. zutil.h skips it
    # when fdopen is already a macro. C only; BioGears' sources are unchanged.
    list(APPEND _praenora_pyenv_biogears_args "-DCMAKE_C_FLAGS=-Dfdopen=fdopen")
endif()
ExternalProject_Add(pyenv_biogears
    DEPENDS pyenv_eigen pyenv_xerces_c
    SOURCE_DIR "${PROJECT_SOURCE_DIR}/${PRAENORA_PYENV_BIOGEARS_PATH}"
    BINARY_DIR "${_praenora_pyenv_work}/biogears/build"
    INSTALL_DIR "${PRAENORA_PYENV_BIOGEARS_PREFIX}"
    CMAKE_ARGS ${_praenora_pyenv_common_args} ${_praenora_pyenv_biogears_args}
    LIST_SEPARATOR |
    DOWNLOAD_COMMAND ""
    UPDATE_COMMAND ""
    USES_TERMINAL_CONFIGURE ON
    USES_TERMINAL_BUILD ON
    USES_TERMINAL_INSTALL ON)

# A new commit of a submodule configures and builds its project again (the sources are local, so
# ExternalProject sees no update of its own).
ExternalProject_Add_StepDependencies(pyenv_eigen configure "${PRAENORA_PYENV_EIGEN_COMMIT_FILE}")
ExternalProject_Add_StepDependencies(pyenv_xerces_c configure
    "${PRAENORA_PYENV_XERCES_C_COMMIT_FILE}")
ExternalProject_Add_StepDependencies(pyenv_biogears configure
    "${PRAENORA_PYENV_BIOGEARS_COMMIT_FILE}")

# What the bundle holds of BioGears and Xerces-C. The script also completes BioGears'
# installation in the build tree with its generated schema headers, which pybiogears includes.
ExternalProject_Get_Property(pyenv_biogears STAMP_DIR)
set(_praenora_pyenv_biogears_stamp "${PROJECT_BINARY_DIR}/stamps/biogears-bundle.stamp")
add_custom_command(OUTPUT "${_praenora_pyenv_biogears_stamp}"
    COMMAND "${CMAKE_COMMAND}"
        "-DBIOGEARS_SOURCE=${PROJECT_SOURCE_DIR}/${PRAENORA_PYENV_BIOGEARS_PATH}"
        "-DBIOGEARS_PREFIX=${PRAENORA_PYENV_BIOGEARS_PREFIX}"
        "-DXERCES_PREFIX=${_praenora_pyenv_xerces_prefix}"
        "-DBUILD_DIR=${_praenora_pyenv_work}"
        "-DLIB_DIR=${CMAKE_INSTALL_PREFIX}/${PRAENORA_PYENV_BIOGEARS_LIB_REL}"
        "-DRUNTIME_DIR=${CMAKE_INSTALL_PREFIX}/${PRAENORA_PYENV_BIOGEARS_RUNTIME_REL}"
        -P "${PROJECT_SOURCE_DIR}/cmake/praenora_pyenv_biogears_bundle.cmake"
    COMMAND "${CMAKE_COMMAND}" -E touch "${_praenora_pyenv_biogears_stamp}"
    DEPENDS pyenv_biogears "${STAMP_DIR}/pyenv_biogears-done"
        "${PROJECT_SOURCE_DIR}/cmake/praenora_pyenv_biogears_bundle.cmake"
    COMMENT "Copying BioGears' libraries and data into the bundle"
    VERBATIM)
add_custom_target(pyenv_biogears_bundle ALL DEPENDS "${_praenora_pyenv_biogears_stamp}")
