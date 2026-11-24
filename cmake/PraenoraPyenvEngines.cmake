# The simulation engines of inflect-sim-core that a bundle can hold, and their selection. Works in
# a configuration and in script mode.
#
# The table lists the engines in the order of inflect-sim-core's viva_simulation_core/engines.py;
# the check python.unittest compares it with that file (docs/upstreams.md#engines).
#
# Defines:
#   PRAENORA_PYENV_KNOWN_ENGINES      tellurium;copasi;biogears;surrogate;rust;julia
#   PRAENORA_PYENV_ENGINE_<NAME>_EXTRA, _MODULE, _DISTRIBUTION, _NEEDS, _STATUS, _NOT_ON
#                                     for each engine (<NAME> in upper case): the extra of
#                                     pyproject.toml, the module that engines.py imports, the
#                                     wrapper distribution, what its build needs beyond a Python
#                                     installation (none, cxx or rust), available or unavailable
#                                     (no upstream extra yet), and the operating systems that do
#                                     not support it
#   praenora_pyenv_resolve_engines(<out> OS <os> [REQUESTED <list>])
#                                     The engines of <list>, checked against the table, in table
#                                     order without duplicates; for an empty <list>, the default
#                                     engines of <os>. Stops the configuration for an unknown
#                                     engine, one that is not available upstream, and one that
#                                     <os> does not support.

include_guard(GLOBAL)

set(PRAENORA_PYENV_KNOWN_ENGINES tellurium copasi biogears surrogate rust julia)

macro(_praenora_pyenv_engine name extra module distribution needs status not_on)
    string(TOUPPER "${name}" _praenora_pyenv_engine_up)
    set(PRAENORA_PYENV_ENGINE_${_praenora_pyenv_engine_up}_EXTRA "${extra}")
    set(PRAENORA_PYENV_ENGINE_${_praenora_pyenv_engine_up}_MODULE "${module}")
    set(PRAENORA_PYENV_ENGINE_${_praenora_pyenv_engine_up}_DISTRIBUTION "${distribution}")
    set(PRAENORA_PYENV_ENGINE_${_praenora_pyenv_engine_up}_NEEDS "${needs}")
    set(PRAENORA_PYENV_ENGINE_${_praenora_pyenv_engine_up}_STATUS "${status}")
    set(PRAENORA_PYENV_ENGINE_${_praenora_pyenv_engine_up}_NOT_ON "${not_on}")
endmacro()

#                       name       extra      module              distribution
#                       needs      status       not_on
_praenora_pyenv_engine(tellurium tellurium viva_tellurium viva-tellurium
                       none available "")
_praenora_pyenv_engine(copasi copasi viva_copasi viva-copasi
                       none available "")
# BioGears is built from source with CodeSynthesis XSD, which is not verified on Windows
# (docs/upstreams.md#biogears).
_praenora_pyenv_engine(biogears biogears viva_biogears viva-biogears
                       cxx available "windows")
_praenora_pyenv_engine(surrogate surrogate viva_torch viva-torch
                       none available "")
_praenora_pyenv_engine(rust rust viva_core viva-core
                       rust available "")
# inflect-sim-core names the engine but has no extra for it yet.
_praenora_pyenv_engine(julia "" viva_julia_diffeqs viva-julia-diffeqs
                       none unavailable "")

function(praenora_pyenv_resolve_engines out)
    cmake_parse_arguments(PARSE_ARGV 1 _arg "" "OS" "REQUESTED")
    if(NOT _arg_OS)
        message(FATAL_ERROR "praenora_pyenv_resolve_engines: OS is not set")
    endif()
    set(_requested ${_arg_REQUESTED})
    if(NOT _requested)
        if(_arg_OS STREQUAL "windows")
            set(_requested tellurium copasi rust)
        else()
            set(_requested tellurium copasi biogears rust)
        endif()
    endif()

    list(JOIN PRAENORA_PYENV_KNOWN_ENGINES ", " _known)
    foreach(_engine IN LISTS _requested)
        if(NOT _engine IN_LIST PRAENORA_PYENV_KNOWN_ENGINES)
            message(FATAL_ERROR "unknown engine ${_engine}; known engines: ${_known}")
        endif()
        string(TOUPPER "${_engine}" _up)
        if(PRAENORA_PYENV_ENGINE_${_up}_STATUS STREQUAL "unavailable")
            message(FATAL_ERROR "${_engine} is not available upstream yet: inflect-sim-core has "
                "no extra for it.")
        endif()
        if(_arg_OS IN_LIST PRAENORA_PYENV_ENGINE_${_up}_NOT_ON)
            message(FATAL_ERROR "${_engine} is not supported on ${_arg_OS} "
                "(docs/upstreams.md).")
        endif()
    endforeach()

    set(_engines "")
    foreach(_engine IN LISTS PRAENORA_PYENV_KNOWN_ENGINES)
        if(_engine IN_LIST _requested)
            list(APPEND _engines "${_engine}")
        endif()
    endforeach()
    set(${out} "${_engines}" PARENT_SCOPE)
endfunction()
