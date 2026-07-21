cmake_minimum_required(VERSION 3.21)
project(plapper_core VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(PLAPPER_BUILD_CAPTURE "Build the miniaudio mic capture layer" ON)
option(PLAPPER_BUILD_TESTS "Build unit tests" ${PROJECT_IS_TOP_LEVEL})
option(PLAPPER_SHARED "Build shared library (FFI use)" ON)

set(PLAPPER_SOURCES src/detector.cpp src/plapper.cpp)
if(PLAPPER_BUILD_CAPTURE)
  list(APPEND PLAPPER_SOURCES capture/capture.cpp)
endif()

if(PLAPPER_SHARED)
  add_library(plapper_core SHARED ${PLAPPER_SOURCES})
  target_compile_definitions(plapper_core PUBLIC PLAPPER_SHARED PRIVATE PLAPPER_BUILDING)
else()
  add_library(plapper_core STATIC ${PLAPPER_SOURCES})
endif()

# output stays libplapper.* regardless of the CMake target name
set_target_properties(plapper_core PROPERTIES OUTPUT_NAME plapper)

if(ANDROID)
  # Android 15 16k page size support
  target_link_options(plapper_core PRIVATE "-Wl,-z,max-page-size=16384")
endif()

target_include_directories(plapper_core
  PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/capture)

if(PLAPPER_BUILD_CAPTURE)
  if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    target_link_libraries(plapper_core PRIVATE dl pthread m)
  elseif(APPLE)
    target_link_libraries(plapper_core PRIVATE
      "-framework CoreAudio" "-framework AudioToolbox" "-framework AVFoundation"
      "-framework Foundation")
  elseif(ANDROID)
    target_link_libraries(plapper_core PRIVATE OpenSLES log)
  endif()
endif()

if(PLAPPER_BUILD_TESTS AND PLAPPER_BUILD_CAPTURE)
  add_executable(plapper_diag tools/diag.cpp)
  target_link_libraries(plapper_diag PRIVATE plapper_core)
endif()

if(PLAPPER_BUILD_TESTS)
  include(FetchContent)
  FetchContent_Declare(catch2
    GIT_REPOSITORY https://github.com/catchorg/Catch2.git
    GIT_TAG v3.7.1)
  FetchContent_MakeAvailable(catch2)

  add_executable(plapper_tests tests/test_detector.cpp)
  target_link_libraries(plapper_tests PRIVATE plapper_core Catch2::Catch2WithMain)
  # tests link the detector directly; capture not needed
  enable_testing()
  add_test(NAME plapper_tests COMMAND plapper_tests)
endif()
