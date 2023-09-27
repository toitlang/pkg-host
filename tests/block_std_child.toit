// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import host.pipe

main:
  stderr := pipe.stderr
  in := pipe.stdin
  out := pipe.stdout

  counter := 0
  task::
    // Repeat enough that this pipe will block until the parent reads
    // from stdout.
    1000.repeat:
      out.write "In the beginning the Universe was created.\n"
      out.write "This has made a lot of people very angry and been widely regarded as a bad move.\n"
      counter++
    stderr.write "Done with stdout."

  // Loop until the other task blocks.
  last_seen := -1
  while last_seen != counter:
    last_seen = counter
    sleep --ms=10

  // If the whole process is blocked then this will not not be
  // printed.
  stderr.write "Message through stderr."
