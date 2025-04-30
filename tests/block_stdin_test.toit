// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import host.pipe
import host.os
import host.file

import .utils

main args:
  if args.size < 1:
    print "Usage: block_std_test.toit <toit_exe>"
    exit 1

  if not file.is-file "tests/block_stdin_child.toit":
    print "Cannot find toit file 'block_stdin_child.toit' in tests directory"
    exit 1

  toit-exe := args[0]

  check-toit-exe toit-exe

  with-compiled --toit-exe=toit-exe "tests/block_stdin_child.toit": | compiled-path/string |
    // We use a compiled executable, so that we don't see compilation warnings of the child program.

    ["close", "read"].do: | action |
      subprocess := pipe.fork
          --create-stdin
          --create-stdout
          compiled-path
          [compiled-path, action]

      print "Started subprocess"

      subprocess-stdin  := subprocess.stdin
      subprocess-stdout := subprocess.stdout
      pid := subprocess.pid

      line := subprocess-stdout.in.read
      expect-equals "Message through stdout." line.to-string
      print "$line.to-string"
      if action == "read":
        subprocess-stdin.out.write "There is an art to flying, or rather a knack.\n"
      else:
        subprocess-stdin.close

      exit-value := subprocess.wait
      expect-equals 0
        pipe.exit-code exit-value
      expect-equals null
        pipe.exit-signal exit-value
      print "OK exit"
