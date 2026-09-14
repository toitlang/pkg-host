// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import host.pipe
import monitor
import system show platform PLATFORM-FREERTOS

import .utils

main args:
  if platform == PLATFORM-FREERTOS: return
  with-compiled --toit-exe=args[0] "tests/pipe_write_child.toit": | exe/string |
    test-delivery exe
    test-delivery exe --chunked
    test-broken-pipe exe
    test-close-during-write exe

test-delivery exe/string --chunked/bool=false:
  process := pipe.fork --create-stdin --create-stderr exe [exe, "read"]
  data := ByteArray (256 * 1024): it & 0x7f
  source := chunked ? data.to-string.byte-slice 0 data.size : data
  expect-equals data.size (process.stdin.out.write source)
  process.stdin.close
  errors := process.stderr.in.read-all
  if errors.size != 0: print errors.to-string
  process.wait
  expect-equals 0 process.exit-code

test-broken-pipe exe/string:
  process := pipe.fork --create-stdin exe [exe, "exit"]
  error := catch: process.stdin.out.write (ByteArray (16 * 1024 * 1024))
  expect (error != null)
  process.stdin.close
  process.wait
  expect-equals 0 process.exit-code

test-close-during-write exe/string:
  process := pipe.fork --create-stdin exe [exe, "idle"]
  started := monitor.Latch
  finished := monitor.Latch
  task::
    started.set true
    finished.set (catch: process.stdin.out.write (ByteArray (16 * 1024 * 1024)))
  started.get
  sleep --ms=100
  process.stdin.close
  error := finished.get
  process.kill --hard
  process.wait
  expect (error != null)
