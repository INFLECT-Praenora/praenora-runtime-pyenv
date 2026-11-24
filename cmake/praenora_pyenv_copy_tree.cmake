# Replaces the directory DESTINATION with a copy of the directory SOURCE, keeping symbolic links as
# links (cmake -E copy_directory copies what they point to). Script mode:
#
#   cmake -DSOURCE=<directory> -DDESTINATION=<directory> -P cmake/praenora_pyenv_copy_tree.cmake

cmake_minimum_required(VERSION 3.24)

foreach(_variable IN ITEMS SOURCE DESTINATION)
    if(NOT DEFINED ${_variable} OR "${${_variable}}" STREQUAL "")
        message(FATAL_ERROR "praenora_pyenv_copy_tree.cmake: ${_variable} is not set")
    endif()
endforeach()
if(NOT IS_DIRECTORY "${SOURCE}")
    message(FATAL_ERROR "praenora_pyenv_copy_tree.cmake: ${SOURCE} is not a directory")
endif()

file(REMOVE_RECURSE "${DESTINATION}")
file(MAKE_DIRECTORY "${DESTINATION}")
file(COPY "${SOURCE}/" DESTINATION "${DESTINATION}" USE_SOURCE_PERMISSIONS)
