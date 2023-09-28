// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import host.pipe

main args:
  closing_test := args[0] == "close"
  in := pipe.stdin
  out := pipe.stdout
  err := pipe.stderr

  task::
    // This blocks, but that should not block the whole VM.
    if closing_test:
      result := in.read
      expect_equals null result
      err.write "Close woke up the task.\n"
    else:
      err.write in.read.to_string

  sleep --ms=100

  // We wake up here even though the read is blocked.
  // This write triggers the parent to do something about our blocked read.
  out.write "Message through stdout."
