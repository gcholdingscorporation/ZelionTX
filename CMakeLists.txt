cmake_minimum_required(VERSION 3.21)

# ZelionTX: a Rotorflight-only, ELRS-only helicopter transmitter firmware.
# Platform layer vendored from EdgeTX (GPL-2.0), see platform/VENDORED.md.
#
# Configure with a preset:  cmake --preset tx15      (firmware, needs arm-none-eabi-gcc)
#                           cmake --preset native    (simulator and tests)
project(ZelionTX C CXX ASM)

set(ZX_VERSION_MAJOR 0)
set(ZX_VERSION_MINOR 1)
set(ZX_VERSION_PATCH 0)
set(ZX_VERSION "${ZX_VERSION_MAJOR}.${ZX_VERSION_MINOR}.${ZX_VERSION_PATCH}")
set(ZX_ROOT ${CMAKE_CURRENT_SOURCE_DIR})

execute_process(
  COMMAND git rev-parse --short=8 HEAD
  WORKING_DIRECTORY ${ZX_ROOT}
  OUTPUT_VARIABLE ZX_GIT_SHA OUTPUT_STRIP_TRAILING_WHITESPACE
  ERROR_QUIET)
if(NOT ZX_GIT_SHA)
  set(ZX_GIT_SHA "unknown")
endif()

set(ZX_TARGET "tx15" CACHE STRING "Target radio: tx15 | tx16smk3 | gx15 | native")
set_property(CACHE ZX_TARGET PROPERTY STRINGS tx15 tx16smk3 gx15 native)

if(ZX_TARGET STREQUAL native)
  message(STATUS "ZelionTX native build (simulator and tests): not yet implemented")
  enable_testing()
  add_subdirectory(tests)
else()
  add_subdirectory(firmware)
endif()
