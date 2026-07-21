cmake_minimum_required(VERSION 3.21)
project(plounter_core VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(PLOUNTER_BUILD_CAPTURE "Build the miniaudio mic capture layer" ON)
option(PLOUNTER_BUILD_TESTS "Build unit tests" ${PROJECT_IS_TOP_LEVEL})
option(PLOUNTER_SHARED "Build shared library (FFI use)" ON)

set(PLOUNTER_SOURCES src/detector.cpp src/plounter.cpp)
if(PLOUNTER_BUILD_CAPTURE)
  list(APPEND PLOUNTER_SOURCES capture/capture.cpp)
endif()

if(PLOUNTER_SHARED)
  add_library(plounter_core SHARED ${PLOUNTER_SOURCES})
  target_compile_definitions(plounter_core PUBLIC PLOUNTER_SHARED PRIVATE PLOUNTER_BUILDING)
else()
  add_library(plounter_core STATIC ${PLOUNTER_SOURCES})
endif()

# output stays libplounter.* regardless of the CMake target name
set_target_properties(plounter_core PROPERTIES OUTPUT_NAME plounter)

if(ANDROID)
  # Android 15 16k page size support
  target_link_options(plounter_core PRIVATE "-Wl,-z,max-page-size=16384")
endif()

target_include_directories(plounter_core
  PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/capture)

if(PLOUNTER_BUILD_CAPTURE)
  if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    target_link_libraries(plounter_core PRIVATE dl pthread m)
  elseif(APPLE)
    target_link_libraries(plounter_core PRIVATE
      "-framework CoreAudio" "-framework AudioToolbox" "-framework AVFoundation"
      "-framework Foundation")
  elseif(ANDROID)
    target_link_libraries(plounter_core PRIVATE OpenSLES log)
  endif()
endif()

if(PLOUNTER_BUILD_TESTS)
  include(FetchContent)
  FetchContent_Declare(catch2
    GIT_REPOSITORY https://github.com/catchorg/Catch2.git
    GIT_TAG v3.7.1)
  FetchContent_MakeAvailable(catch2)

  add_executable(plounter_tests tests/test_detector.cpp)
  target_link_libraries(plounter_tests PRIVATE plounter_core Catch2::Catch2WithMain)
  # tests link the detector directly; capture not needed
  enable_testing()
  add_test(NAME plounter_tests COMMAND plounter_tests)
endif()
