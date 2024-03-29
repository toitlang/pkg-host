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

  crash-exe := args[1]

  run-crash := : | signal/int? |
    signal-arg := signal ? ["$signal"] : []
    pipes := pipe.fork
      true  // use_path
      pipe.PIPE-CREATED  // stdin
      pipe.PIPE-CREATED  // stdout
      pipe.PIPE-CREATED  // stderr
      crash-exe
      [crash-exe] + signal-arg

    pid := pipes[3]
    pipe.wait-for pid

  signals-to-test := [
    4, // SIGILL
    15, // SIGTERM
  ]
  if platform != PLATFORM-WINDOWS:
    signals-to-test += [
      9, // SIGKILL
    ]

  signals-to-test.do: |signal|
    exit-value := run-crash.call signal
    expect-equals signal (pipe.exit-signal exit-value)
