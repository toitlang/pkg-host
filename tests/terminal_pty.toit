// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import io
import host.terminal

main:
  expect (terminal.is-terminal 0)
  expect (terminal.is-terminal 1)
  expect-not (terminal.is-terminal -1)
  expect-size 80 24

  mode := terminal.RawMode
  print "RAW"
  input := io.stdin.read
  expect (input and input.size == 1 and input[0] == 'x')

  expect-equals "ALREADY_IN_USE" (catch: terminal.RawMode)
  mode.restore
  mode.restore  // Idempotent.
  terminal.with-raw-mode: null
  print "RESTORED"

  resize := terminal.ResizeWatcher
  expect-equals (terminal.size) resize.last
  print "WATCHING"
  changed := resize.wait
  expect-equals 100 changed.columns
  expect-equals 30 changed.rows
  expect-equals changed resize.last
  expect-size 100 30
  resize.close
  print "DONE"

expect-size expected-columns/int expected-rows/int -> none:
  size := terminal.size
  expect-equals expected-columns size.columns
  expect-equals expected-rows size.rows
  expect-null size.pixel-width
  expect-null size.pixel-height
