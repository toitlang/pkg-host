// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import expect show *

import host.directory show *
import host.file
import host.pipe

main args:
  // This test does not work on ESP32 since you can't launch subprocesses.
  if platform == "FreeRTOS": return

  crash_exe := args[0]

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
