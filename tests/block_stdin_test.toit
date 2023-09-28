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

  if not file.is_file "tests/block_stdout_child.toit":
    print "Cannot find toit file 'block_stdout_child.toit' in tests directory"
    exit 1

  if not file.is_file "tests/block_stdin_child.toit":
    print "Cannot find toit file 'block_stdin_child.toit' in tests directory"
    exit 1

  toit_exe := args[0]

  // Try to run the toit executable.
  exception := catch: pipe.backticks toit_exe "--version"
  if exception:
    print "Running the given toit executable '$toit_exe' failed: $exception"
    exit 1

  ["close", "read"].do: | action |
    subprocess := pipe.fork
      true  // use_path
      pipe.PIPE_CREATED   // stdin
      pipe.PIPE_CREATED   // stdout
      pipe.PIPE_INHERITED // stderr
      toit_exe
      [toit_exe, "tests/block_stdin_child.toit", action]

    subprocess_stdin  := subprocess[0]
    subprocess_stdout := subprocess[1]
    pid := subprocess[3]

    line := subprocess_stdout.read
    expect_equals "Message through stdout." line.to_string
    print "$line.to_string"
    if action == "read":
      subprocess_stdin.write "There is an art to flying, or rather a knack.\n"
    else:
      subprocess_stdin.close

    exit_value := pipe.wait_for pid
    expect_equals 0
      pipe.exit_code exit_value
    expect_equals null
      pipe.exit_signal exit_value
    print "OK exit"
