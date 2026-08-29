// Copyright (C) 2026 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import host.pipe
import system show platform PLATFORM-FREERTOS PLATFORM-WINDOWS

SIGKILL ::= 9
SIGTERM ::= 15

main:
  // FreeRTOS cannot launch host subprocesses.
  if platform == PLATFORM-FREERTOS: return

  test-kill
  test-hard-kill
  test-invalid-grace-period
  test-signal
  if platform != PLATFORM-WINDOWS:
    test-ignored-signal
    test-handled-signal

test-kill:
  process := pipe.fork --create-stdin "cat" ["cat"]
  process.kill
  exit-value := with-timeout --ms=1_000: process.wait
  expected-signal := platform == PLATFORM-WINDOWS ? SIGKILL : SIGTERM
  expect-equals expected-signal (pipe.exit-signal exit-value)

test-hard-kill:
  process := pipe.fork --create-stdin "cat" ["cat"]
  process.kill --hard-after-ms=0
  exit-value := with-timeout --ms=1_000: process.wait
  expect-equals SIGKILL (pipe.exit-signal exit-value)

test-invalid-grace-period:
  process := pipe.fork --create-stdin "cat" ["cat"]
  expect-throw "OUT_OF_RANGE": process.kill --hard-after-ms=-1
  process.kill --hard-after-ms=0
  process.wait

test-signal:
  process := pipe.fork --create-stdin "cat" ["cat"]
  process.signal SIGKILL
  exit-value := with-timeout --ms=1_000: process.wait
  expect-equals SIGKILL (pipe.exit-signal exit-value)

test-ignored-signal:
  // Wait for the shell to install the handler before sending the signal.
  process := pipe.fork
      --create-stdout
      "sh"
      ["sh", "-c", "trap '' TERM; echo ready; exec sleep 60"]
  process.stdout.in.read

  process.kill --hard-after-ms=20
  exit-value := with-timeout --ms=1_000: process.wait
  expect-equals SIGKILL (pipe.exit-signal exit-value)

test-handled-signal:
  // A process that handles SIGTERM must not receive the scheduled SIGKILL.
  process := pipe.fork
      --create-stdout
      "sh"
      ["sh", "-c", "trap 'exit 42' TERM; echo ready; while :; do :; done"]
  process.stdout.in.read

  process.kill --hard-after-ms=100
  exit-value := with-timeout --ms=1_000: process.wait
  expect-equals 42 (pipe.exit-code exit-value)
