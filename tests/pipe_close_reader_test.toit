// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import host.pipe
import monitor
import system show platform PLATFORM-FREERTOS

import .utils

// The number of times the racy close is attempted.
ATTEMPTS ::= 100

main args:
  // FreeRTOS cannot launch host subprocesses.
  if platform == PLATFORM-FREERTOS: return

  if args.size < 1:
    print "Usage: pipe_close_reader_test.toit <toit_exe>"
    exit 1
  toit-exe := args[0]

  with-compiled --toit-exe=toit-exe "tests/pipe_close_reader_child.toit": | exe/string |
    test-close-blocked-read exe
    test-close-during-read exe

/**
Closes a pipe while another task is blocked reading from it.

The reader must abort and report the end of the data instead of throwing.
*/
test-close-blocked-read exe/string:
  process := pipe.fork --create-stdout exe [exe, "idle"]
  reader := process.stdout.in
  result := null
  latch := monitor.Latch
  task::
    latch.set (catch: result = reader.try-ensure-buffered 1)

  // Give the reading task time to block.
  sleep --ms=100
  reader.close

  expect-null latch.get
  expect-equals false result

  process.kill --hard
  process.wait

/**
Closes a pipe while another task is reading from it at full speed.

The reader must not see the 'ALREADY_CLOSED' error of the underlying resource.
*/
test-close-during-read exe/string:
  ATTEMPTS.repeat: | attempt/int |
    process := pipe.fork --create-stdout exe [exe, "spew"]
    reader := process.stdout.in
    // Wait for the first chunk, so that the child is up and running and the
    // close below really competes with a read.
    reader.read
    latch := monitor.Latch
    task::
      latch.set (catch:
        while reader.try-ensure-buffered 1:
          reader.skip reader.buffered-size)

    // Vary the delay, so that the close hits different points of the read.
    sleep --ms=(attempt % 7)
    reader.close

    exception := latch.get
    process.kill --hard
    process.wait
    expect-null exception
