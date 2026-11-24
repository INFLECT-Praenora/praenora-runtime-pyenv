# Platform, compiler and Python labels of the bundle.
#
# The labels name the bundle (PRAENORA_PYENV_PACKAGE_NAME) and go into its manifest and CMake
# package, where the Praenora runtime's build can check them (docs/outputs.md). Platform names are
# the runtime's: linux, macos or windows, and x86_64 or arm64.
#
# Afterwards these exist:
#   PRAENORA_PYENV_OS                 linux, macos or windows
#   PRAENORA_PYENV_ARCH               x86_64 or arm64
#   PRAENORA_PYENV_PLATFORM_KEY       MACOS_ARM64, LINUX_X86_64 or WINDOWS_X86_64 (selects the
#                                     CPython archive of cmake/PraenoraPyenvVersions.cmake)
#   PRAENORA_PYENV_OS_MIN_VERSION     macOS: CMAKE_OSX_DEPLOYMENT_TARGET; elsewhere empty
#   PRAENORA_PYENV_DISTRIBUTION       Linux: <id>-<version> from /etc/os-release; elsewhere empty
#   PRAENORA_PYENV_COMPILER_ID        CMAKE_CXX_COMPILER_ID
#   PRAENORA_PYENV_COMPILER_VERSION   CMAKE_CXX_COMPILER_VERSION
#   PRAENORA_PYENV_COMPILER_LABEL     appleclang<major>, clang<major>, gcc<major> or msvc<toolset>
#   PRAENORA_PYENV_CXX_STDLIB         libc++, libstdc++ or msvc-stl
#   PRAENORA_PYENV_MSVC_RUNTIME       MSVC: MultiThreadedDLL; elsewhere empty
#   PRAENORA_PYENV_CONFIG_LABEL       release
#   PRAENORA_PYENV_PACKAGE_NAME       praenora-runtime-pyenv-<version>-<os>-<arch>-<python>-
#                                     <compiler>-<config>

include_guard(GLOBAL)
include(CheckCXXSourceCompiles)

# Release only: the interpreter is a release build, and each extension module carries its own C
# runtime library (docs/building.md#presets).
get_property(_praenora_pyenv_multi_config GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(_praenora_pyenv_multi_config)
    message(FATAL_ERROR "praenora-runtime-pyenv needs a single-configuration generator such as "
        "Ninja; ${CMAKE_GENERATOR} is multi-configuration.")
endif()
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Release" FORCE)
endif()
if(NOT CMAKE_BUILD_TYPE STREQUAL "Release")
    message(FATAL_ERROR "CMAKE_BUILD_TYPE is '${CMAKE_BUILD_TYPE}'; bundles are Release only.")
endif()
set(PRAENORA_PYENV_CONFIG_LABEL release)

# Operating system.
set(PRAENORA_PYENV_OS_MIN_VERSION "")
set(PRAENORA_PYENV_DISTRIBUTION "")
if(APPLE)
    set(PRAENORA_PYENV_OS macos)
    if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
        message(FATAL_ERROR "CMAKE_OSX_DEPLOYMENT_TARGET is empty; set it (14.0 by default).")
    endif()
    set(PRAENORA_PYENV_OS_MIN_VERSION "${CMAKE_OSX_DEPLOYMENT_TARGET}")
elseif(WIN32)
    set(PRAENORA_PYENV_OS windows)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(PRAENORA_PYENV_OS linux)
    cmake_host_system_information(RESULT _praenora_pyenv_distrib_id QUERY DISTRIB_ID)
    cmake_host_system_information(RESULT _praenora_pyenv_distrib_version
        QUERY DISTRIB_VERSION_ID)
    if(_praenora_pyenv_distrib_id)
        set(PRAENORA_PYENV_DISTRIBUTION
            "${_praenora_pyenv_distrib_id}-${_praenora_pyenv_distrib_version}")
    endif()
else()
    message(FATAL_ERROR "praenora-runtime-pyenv builds on Linux, macOS and Windows only, not on "
        "${CMAKE_SYSTEM_NAME}.")
endif()

# Architecture: one per bundle.
if(APPLE)
    if(NOT CMAKE_OSX_ARCHITECTURES)
        set(CMAKE_OSX_ARCHITECTURES "${CMAKE_HOST_SYSTEM_PROCESSOR}" CACHE STRING
            "Target architecture (one)" FORCE)
    endif()
    list(LENGTH CMAKE_OSX_ARCHITECTURES _praenora_pyenv_arch_count)
    if(NOT _praenora_pyenv_arch_count EQUAL 1)
        message(FATAL_ERROR "CMAKE_OSX_ARCHITECTURES names ${_praenora_pyenv_arch_count} "
            "architectures (${CMAKE_OSX_ARCHITECTURES}); a bundle holds one.")
    endif()
    set(_praenora_pyenv_arch "${CMAKE_OSX_ARCHITECTURES}")
elseif(MSVC)
    set(_praenora_pyenv_arch "${CMAKE_CXX_COMPILER_ARCHITECTURE_ID}")
else()
    set(_praenora_pyenv_arch "${CMAKE_SYSTEM_PROCESSOR}")
endif()
if(_praenora_pyenv_arch MATCHES "^(x86_64|AMD64|amd64|x64)$")
    set(PRAENORA_PYENV_ARCH x86_64)
elseif(_praenora_pyenv_arch MATCHES "^(arm64|ARM64|aarch64)$")
    set(PRAENORA_PYENV_ARCH arm64)
else()
    message(FATAL_ERROR "Unsupported architecture '${_praenora_pyenv_arch}'; x86_64 and arm64 "
        "are supported.")
endif()
if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "praenora-runtime-pyenv builds 64-bit binaries only.")
endif()
string(TOUPPER "${PRAENORA_PYENV_OS}_${PRAENORA_PYENV_ARCH}" PRAENORA_PYENV_PLATFORM_KEY)
if(NOT DEFINED PRAENORA_PYENV_PYTHON_${PRAENORA_PYENV_PLATFORM_KEY}_ARCHIVE)
    message(FATAL_ERROR "No CPython archive is pinned for ${PRAENORA_PYENV_OS} "
        "${PRAENORA_PYENV_ARCH} (cmake/PraenoraPyenvVersions.cmake).")
endif()

# Compiler. The C and C++ compilers must come from one toolchain.
if(NOT CMAKE_C_COMPILER_ID STREQUAL CMAKE_CXX_COMPILER_ID OR
   NOT CMAKE_C_COMPILER_VERSION VERSION_EQUAL CMAKE_CXX_COMPILER_VERSION)
    message(FATAL_ERROR "The C compiler (${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION}) and "
        "the C++ compiler (${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}) differ.")
endif()
set(PRAENORA_PYENV_COMPILER_ID "${CMAKE_CXX_COMPILER_ID}")
set(PRAENORA_PYENV_COMPILER_VERSION "${CMAKE_CXX_COMPILER_VERSION}")
string(REGEX MATCH "^[0-9]+" _praenora_pyenv_compiler_major "${CMAKE_CXX_COMPILER_VERSION}")
if(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
    set(PRAENORA_PYENV_COMPILER_LABEL "appleclang${_praenora_pyenv_compiler_major}")
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    set(PRAENORA_PYENV_COMPILER_LABEL "clang${_praenora_pyenv_compiler_major}")
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    set(PRAENORA_PYENV_COMPILER_LABEL "gcc${_praenora_pyenv_compiler_major}")
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
    set(PRAENORA_PYENV_COMPILER_LABEL "msvc${MSVC_TOOLSET_VERSION}")
else()
    message(FATAL_ERROR "Unsupported compiler ${CMAKE_CXX_COMPILER_ID}; use AppleClang, Clang, "
        "GCC or MSVC.")
endif()

# C++ standard library, as the compiler sees it.
foreach(_praenora_pyenv_stdlib IN ITEMS "LIBCXX|_LIBCPP_VERSION" "LIBSTDCXX|__GLIBCXX__"
                                        "MSVC_STL|_MSVC_STL_VERSION")
    string(REPLACE "|" ";" _praenora_pyenv_stdlib "${_praenora_pyenv_stdlib}")
    list(GET _praenora_pyenv_stdlib 0 _praenora_pyenv_stdlib_name)
    list(GET _praenora_pyenv_stdlib 1 _praenora_pyenv_stdlib_macro)
    check_cxx_source_compiles("#include <cstddef>
#ifndef ${_praenora_pyenv_stdlib_macro}
#error
#endif
int main() { return 0; }" PRAENORA_PYENV_HAS_${_praenora_pyenv_stdlib_name})
endforeach()
if(PRAENORA_PYENV_HAS_LIBCXX)
    set(PRAENORA_PYENV_CXX_STDLIB libc++)
elseif(PRAENORA_PYENV_HAS_LIBSTDCXX)
    set(PRAENORA_PYENV_CXX_STDLIB libstdc++)
elseif(PRAENORA_PYENV_HAS_MSVC_STL)
    set(PRAENORA_PYENV_CXX_STDLIB msvc-stl)
else()
    message(FATAL_ERROR "The C++ standard library of ${CMAKE_CXX_COMPILER} is not recognized.")
endif()

# MSVC runtime library: the shared one (/MD), as the Praenora runtime and CPython use.
set(PRAENORA_PYENV_MSVC_RUNTIME "")
if(MSVC)
    if(DEFINED CMAKE_MSVC_RUNTIME_LIBRARY AND
       NOT CMAKE_MSVC_RUNTIME_LIBRARY STREQUAL "MultiThreadedDLL")
        message(FATAL_ERROR "CMAKE_MSVC_RUNTIME_LIBRARY is '${CMAKE_MSVC_RUNTIME_LIBRARY}'; the "
            "bundle needs the shared release runtime library (/MD).")
    endif()
    set(PRAENORA_PYENV_MSVC_RUNTIME MultiThreadedDLL)
endif()

set(PRAENORA_PYENV_PACKAGE_NAME "praenora-runtime-pyenv-${PROJECT_VERSION}-${PRAENORA_PYENV_OS}-\
${PRAENORA_PYENV_ARCH}-${PRAENORA_PYENV_PYTHON_ABI}-${PRAENORA_PYENV_COMPILER_LABEL}-\
${PRAENORA_PYENV_CONFIG_LABEL}")

message(STATUS "praenora-runtime-pyenv: bundle ${PRAENORA_PYENV_PACKAGE_NAME}")
message(STATUS "praenora-runtime-pyenv: ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION} "
    "(${PRAENORA_PYENV_CXX_STDLIB}), CPython ${PRAENORA_PYENV_PYTHON_VERSION}")
if(PRAENORA_PYENV_OS_MIN_VERSION)
    message(STATUS
        "praenora-runtime-pyenv: macOS deployment target ${PRAENORA_PYENV_OS_MIN_VERSION}")
endif()
message(STATUS "praenora-runtime-pyenv: bundle directory ${CMAKE_INSTALL_PREFIX}")
