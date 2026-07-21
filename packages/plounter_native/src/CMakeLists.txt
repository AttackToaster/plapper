# Thin wrapper: builds the real plounter core (../../../core) for every
# platform that consumes this file (Android gradle directly; the linux/ and
# windows/ plugin CMakeLists via add_subdirectory).
cmake_minimum_required(VERSION 3.21)

project(plounter_native_library VERSION 0.1.0 LANGUAGES C CXX)

set(PLOUNTER_BUILD_TESTS OFF CACHE BOOL "" FORCE)

# Flutter consumes plugins through ephemeral symlinks; resolve the real
# location first or the relative hop to the repo root lands in ephemeral/.
get_filename_component(PLOUNTER_PKG_SRC "${CMAKE_CURRENT_LIST_DIR}" REALPATH)
add_subdirectory("${PLOUNTER_PKG_SRC}/../../../core" plounter_core_build)
