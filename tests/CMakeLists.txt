# Copyright (C) 2022 Toitware ApS.
# Use of this source code is governed by a Zero-Clause BSD license that can
# be found in the tests/LICENSE file.

file(GLOB TESTS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} "*_test.toit" "*_test_slow.toit")

# Add windows exe extension.
set(TOIT_EXEC "toit${CMAKE_EXECUTABLE_SUFFIX}" CACHE FILEPATH "The executable used to run the tests")
set(TEST_TIMEOUT 40 CACHE STRING "The maximal amount of time each test is allowed to run")
set(SLOW_TEST_TIMEOUT 200 CACHE STRING "The maximal amount of time each slow test is allowed to run")

add_custom_target(
  "install-pkgs"
  COMMAND "${TOIT_EXEC}" pkg install
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)

add_executable(
  crash
  crash.cc
  )

include(ProcessorCount)
ProcessorCount(NUM_CPU)

# Add a custom target 'check' that runs our unit tests.
add_custom_target(
  "check"
  COMMAND "${CMAKE_CTEST_COMMAND}" -j${NUM_CPU} --output-on-failure -C Debug
  USES_TERMINAL
)

set(TEST_PREFIX "")
# Tests that fail locally and on toitlang/toit.
include(fail.cmake OPTIONAL)
# Tests that only fail when called with this test runner.
include(fail_pkg.cmake OPTIONAL)

message("Failing tests: ${FAILING_TESTS}")
message("Skipped tests: ${SKIP_TESTS}")

foreach(file ${TESTS})
  set(test_name "/tests/${file}")
  if("${test_name}" IN_LIST SKIP_TESTS)
    continue()
  endif()

  add_test(
    NAME "${test_name}"
    COMMAND "${TOIT_EXEC}" run "tests/${file}" -- ${TOIT_EXEC} $<TARGET_FILE:crash>
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
  )

  if ("${file}" MATCHES "slow.toit")
    set_tests_properties(${test_name} PROPERTIES TIMEOUT ${SLOW_TEST_TIMEOUT})
  else()
    set_tests_properties(${test_name} PROPERTIES TIMEOUT ${TEST_TIMEOUT})
  endif()

  if ("${test_name}" IN_LIST FAILING_TESTS)
    set_tests_properties("${test_name}" PROPERTIES WILL_FAIL TRUE)
  endif()

endforeach()

# The terminal test needs a pseudo-terminal, which the runner provides.
if(UNIX)
  add_executable(terminal_test_runner terminal_test_runner_posix.cc)
  find_library(TERMINAL_UTIL_LIBRARY util)
  if(TERMINAL_UTIL_LIBRARY)
    target_link_libraries(terminal_test_runner PRIVATE ${TERMINAL_UTIL_LIBRARY})
  endif()
elseif(WIN32)
  add_executable(terminal_test_runner terminal_test_runner_win.cc)
endif()

if(TARGET terminal_test_runner)
  add_test(
    NAME "/tests/terminal_pty.toit"
    COMMAND $<TARGET_FILE:terminal_test_runner> "${TOIT_EXEC}" run "tests/terminal_pty.toit"
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
  )
  set_tests_properties("/tests/terminal_pty.toit" PROPERTIES TIMEOUT ${TEST_TIMEOUT})
endif()
