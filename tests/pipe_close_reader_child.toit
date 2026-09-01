// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import host.pipe

/**
Helper for 'pipe_close_reader_test.toit'.

With the "idle" argument the program just waits, so that the parent's read
  blocks. Otherwise it writes small chunks with pauses in between, so that the
  parent's read is repeatedly blocked and then woken up again.
*/
main args:
  if args[0] == "idle":
    sleep --ms=30_000
    return

  // The parent closes its end of the pipe, so the writes are expected to fail.
  catch:
    while true:
      pipe.stdout.out.write "hello\n"
      sleep --ms=1
