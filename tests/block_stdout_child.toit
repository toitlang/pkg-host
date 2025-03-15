// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import host.file
import host.pipe

main args:
  closing-test := args[0] == "close"
  stderr := pipe.stderr
  in := pipe.stdin
  out := pipe.stdout

  counter := 0
  task::
    // Repeat enough that this pipe will block until the parent reads
    // from stdout.
    1000.repeat:
      out.out.write "In the beginning the Universe was created.\n"
      out.out.write "This has made a lot of people very angry and been widely regarded as a bad move.\n"
      counter++
    if not closing-test:
      stderr.out.write "Done with stdout."

  // Loop until the other task blocks.
  last-seen := -1
  while last-seen != counter:
    last-seen = counter
    sleep --ms=10

  if closing-test:
    // If the whole process is blocked then the pipe will not be closed.
    stderr.close
  else:
    // If the whole process is blocked then this will not not be written.
    stderr.out.write "Message through stderr."
