// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import host.directory show *
import host.file
import host.pipe
import system show platform PLATFORM-FREERTOS PLATFORM-WINDOWS

main args:
  // This test does not work on ESP32 since you can't launch subprocesses.
  if platform == PLATFORM-FREERTOS: return

  // This test gets called by the external test script on the SDK, which does
  // not pass two arguments.
  if args.size < 2: return

  crash_exe := args[1]

  run_crash := : | signal/int? |
    signal_arg := signal ? ["$signal"] : []
    pipes := pipe.fork
      true  // use_path
      pipe.PIPE_CREATED  // stdin
      pipe.PIPE_CREATED  // stdout
      pipe.PIPE_CREATED  // stderr
      crash_exe
      [crash_exe] + signal_arg

    pid := pipes[3]
    pipe.wait_for pid

  signals_to_test := [
    4, // SIGILL
    15, // SIGTERM
  ]
  if platform != PLATFORM_WINDOWS:
    signals_to_test += [
      9, // SIGKILL
    ]

  signals_to_test.do: |signal|
    exit_value := run_crash.call signal
    expect_equals signal (pipe.exit_signal exit_value)
