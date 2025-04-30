// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import host.pipe
import host.os
import host.file
import semver

import .utils

tt [block]: block.call
main args:
  if args.size < 1:
    print "Usage: block_std_test.toit <toit_exe>"
    exit 1

  if not file.is-file "tests/block_stdout_child.toit":
    print "Cannot find toit file 'block_stdout_child.toit' in tests directory"
    exit 1

  toit-exe := args[0]

  // check-toit-exe toit-exe

  with-compiled --toit-exe=toit-exe "tests/block_stdout_child.toit": | compiled-path/string |
    // We use an executable, so that we don't see compilation warnings of the child program.

    ["close", "write"].do: | action |
      print "Running $compiled-path $action"
      subprocess := pipe.fork
          --create-stdout
          --create-stderr
          compiled-path
          [compiled-path, action]

      subprocess-stdout := subprocess.stdout
      subprocess-stderr := subprocess.stderr

      // Get the stderr first even though the subproces is blocking on stdout.
      print "Waiting for read of child stderr."
      line := subprocess-stderr.in.read
      // If this gets the wrong message then the buffer on stdout is too big and
      // we need to increase the size of the loop in block_stdout_child.toit.
      if action == "close":
        if line != null: print "<$line.to-string>"
        expect-equals null line
        print "Close woke up the task."
      else:
        expect-equals "Message through stderr." line.to-string
        print "$line.to-string"
      task::
        while read := subprocess-stdout.in.read:
          null
      if action != "close":
        line = subprocess-stderr.in.read
        expect-equals "Done with stdout." line.to-string
        print "$line.to-string"

      exit-value := subprocess.wait
      expect-equals 0
        pipe.exit-code exit-value
      expect-equals null
        pipe.exit-signal exit-value
      print "OK exit"
