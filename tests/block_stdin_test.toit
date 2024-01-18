// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import host.pipe
import host.os
import host.file

main args:
  if args.size < 1:
    print "Usage: block_std_test.toit <toit_exe>"
    exit 1

  if not file.is-file "tests/block_stdout_child.toit":
    print "Cannot find toit file 'block_stdout_child.toit' in tests directory"
    exit 1

  if not file.is-file "tests/block_stdin_child.toit":
    print "Cannot find toit file 'block_stdin_child.toit' in tests directory"
    exit 1

  toit-exe := args[0]

  // Try to run the toit executable.
  print "Trying to run $toit-exe"
  exception := catch: pipe.backticks toit-exe "--version"
  if exception:
    print "Running the given toit executable '$toit-exe' failed: $exception"
    exit 1

  print "Managed to run $toit-exe"

  ["close", "read"].do: | action |
    subprocess := pipe.fork
      true  // use_path
      pipe.PIPE-CREATED   // stdin
      pipe.PIPE-CREATED   // stdout
      pipe.PIPE-INHERITED // stderr
      toit-exe
      [toit-exe, "tests/block_stdin_child.toit", action]

    print "Started subprocess"

    subprocess-stdin  := subprocess[0]
    subprocess-stdout := subprocess[1]
    pid := subprocess[3]

    line := subprocess-stdout.read
    expect-equals "Message through stdout." line.to-string
    print "$line.to-string"
    if action == "read":
      subprocess-stdin.write "There is an art to flying, or rather a knack.\n"
    else:
      subprocess-stdin.close

    exit-value := pipe.wait-for pid
    expect-equals 0
      pipe.exit-code exit-value
    expect-equals null
      pipe.exit-signal exit-value
    print "OK exit"
