// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import monitor
import host.signal
import system show platform PLATFORM-FREERTOS PLATFORM-MACOS PLATFORM-WINDOWS

main:
  test-numbers
  if platform == PLATFORM-FREERTOS: return
  test-watch-each
  test-watcher
  test-handle
  test-helpers
  test-coalescing
  if platform != PLATFORM-WINDOWS: test-ignore

ALL ::= [
  signal.HUP,
  signal.INT,
  signal.QUIT,
  signal.KILL,
  signal.USR1,
  signal.USR2,
  signal.PIPE,
  signal.ALRM,
  signal.TERM,
  signal.CHLD,
  signal.CONT,
  signal.STOP,
  signal.TSTP,
  signal.TTIN,
  signal.TTOU,
  signal.WINCH,
  signal.BREAK,
  signal.INFO,
]
WINDOWS ::= [signal.INT, signal.KILL, signal.TERM, signal.WINCH, signal.BREAK]
POSIX ::= ALL.filter: it != signal.BREAK and it != signal.INFO
MACOS ::= POSIX + [signal.INFO]
// Can only be sent.
UNCATCHABLE ::= [signal.KILL, signal.STOP]

supported -> List:
  if platform == PLATFORM-FREERTOS: return []
  if platform == PLATFORM-WINDOWS: return WINDOWS
  if platform == PLATFORM-MACOS: return MACOS
  return POSIX

test-numbers:
  ALL.do: | sig/signal.Signal |
    expect-equals (supported.contains sig) sig.is-supported
    expect-equals sig.is-supported (sig.number != null)
    if sig.number: expect-identical sig (signal.Signal.from-number sig.number)
  if platform == PLATFORM-FREERTOS: return

  expect-null (signal-number_ "BOGUS")
  expect-equals signal.INT.number (signal-number_ "INT")
  expect-null (signal.Signal.from-number 0)
  expect-null (signal.Signal.from-number 1000)

  // The numbers that are the same on every platform that has them, so code
  // may use them directly.
  expect-equals 2 signal.INT.number
  expect-equals 15 signal.TERM.number
  expect-equals 9 signal.KILL.number
  if platform != PLATFORM-WINDOWS: expect-equals 1 signal.HUP.number

  UNCATCHABLE.do: | sig/signal.Signal |
    if sig.is-supported:
      expect-equals "INVALID_ARGUMENT" (catch: signal.Watcher [sig])
      expect-equals "INVALID_ARGUMENT" (catch: signal.ignore sig)
      expect-equals "INVALID_ARGUMENT" (catch: signal.reset sig)

// Every catchable signal can be watched and is delivered. Only raised while
// watched, since the default action of some (TSTP, TTIN, TTOU) would stop the
// test.
test-watch-each:
  supported.do: | sig/signal.Signal |
    if UNCATCHABLE.contains sig: continue.do
    watcher := signal.Watcher [sig]
    try:
      signal.raise sig
      expect-identical sig watcher.wait
    finally:
      watcher.close

test-watcher:
  expect-equals "INVALID_ARGUMENT" (catch: signal.Watcher [])
  // Duplicates are harmless.
  (signal.Watcher [signal.INT, signal.INT]).close
  // Platform numbers are accepted, unknown ones are not.
  (signal.Watcher [signal.INT.number]).close
  expect-equals "UNSUPPORTED" (catch: signal.Watcher [1000])

  watcher := signal.Watcher [signal.INT, signal.TERM]

  // Test that timeouts are handled cleanly.
  expect-throw "DEADLINE_EXCEEDED":
    with-timeout --ms=50:
      watcher.wait

  signal.raise signal.TERM
  expect-identical signal.TERM watcher.wait
  expect-equals "TERM" "$signal.TERM"

  signal.raise signal.INT.number
  expect-identical signal.INT watcher.wait

  signal.raise signal.INT
  signal.raise signal.TERM
  expect-equals {signal.INT, signal.TERM} {watcher.wait, watcher.wait}

  // Multiple watchers see the same signal.
  single := signal.Watcher [signal.INT]
  signal.raise signal.INT
  expect-identical signal.INT single.wait
  expect-identical signal.INT watcher.wait
  single.close
  single.close  // Idempotent.
  expect-equals "CLOSED" (catch: single.wait)

  // Signals coalesce, so raise the next one only after the previous one
  // was delivered.
  received := []
  signal.raise signal.TERM
  watcher.do: | sig/signal.Signal |
    received.add sig
    if received.size == 3:
      // Closing the watcher should exit the "do".
      watcher.close
      continue.do
    signal.raise signal.TERM
  expect-equals [signal.TERM, signal.TERM, signal.TERM] received

test-handle:
  // The outer watcher keeps the handler installed while the task raises, so
  // a signal that arrives before the helper's watcher exists is harmless.
  outer := signal.Watcher [signal.TERM]
  received := []
  done := monitor.Latch

  task::
    signal.handle [signal.TERM]: | sig/signal.Signal |
      received.add sig
      if received.size >= 3:
        // Exits the lambda, so nothing after the handle call runs.
        done.set true
        continue.task

  while received.size < 3:
    signal.raise signal.TERM
    sleep --ms=5

  done.get
  outer.close

test-helpers:
  // The outer watcher keeps the handler installed while the task raises, so
  // a signal that arrives before the helper's watcher exists is harmless.
  outer := signal.Watcher [signal.TERM]
  received := []

  // Test that timeouts are handled cleanly.
  expect-throw "DEADLINE_EXCEEDED":
    with-timeout --ms=50:
      signal.wait [signal.TERM]

  task::
    sig := signal.wait [signal.TERM]
    received.add sig

  while received.is-empty:
    signal.raise signal.TERM
    sleep --ms=5

  expect-equals [signal.TERM] received
  outer.close

test-coalescing:
  watcher := signal.Watcher [signal.TERM]
  5.repeat:
    signal.raise signal.TERM

  // Let the event thread deliver the signal(s).
  sleep --ms=50
  expect-identical signal.TERM watcher.wait

  // Nothing should be left over.
  expect-throw "DEADLINE_EXCEEDED":
    with-timeout --ms=25:
      watcher.wait
  watcher.close

test-ignore:
  signal.ignore signal.USR1
  signal.raise signal.USR1  // Survives.
  usr := signal.Watcher [signal.USR1]
  signal.raise signal.USR1
  expect-identical signal.USR1 usr.wait
  usr.close
  signal.raise signal.USR1  // Still ignored.

  // Numbers work here too.
  signal.ignore signal.USR2.number
  signal.raise signal.USR2.number  // Survives.
  signal.reset signal.USR2.number

signal-number_ name/string:
  #primitive.signal.number
