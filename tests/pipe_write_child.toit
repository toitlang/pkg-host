// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import host.pipe
import expect show *

main args:
  if args[0] == "idle":
    sleep --ms=30_000
    return
  // Let the parent's write exceed the Windows pipe buffer before reading.
  sleep --ms=100
  if args[0] == "exit": return
  data := pipe.stdin.in.read-all
  expect-equals 256 * 1024 data.size
  data.size.repeat: expect-equals (it & 0x7f) data[it]
