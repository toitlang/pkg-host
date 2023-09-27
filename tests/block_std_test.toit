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

  if not file.is_file "tests/block_std_child.toit":
    print "Cannot find toit file 'block_std_child.toit' in tests directory"
    exit 1

  toit_exe := args[0]

  // Try to run the toit executable.
  exception := catch: pipe.backticks toit_exe "--version"
  if exception:
    print "Running the given toit executable '$toit_exe' failed: $exception"
    exit 1

  subprocess := pipe.fork
    true  // use_path
    pipe.PIPE_INHERITED // stdin
    pipe.PIPE_CREATED   // stdout
    pipe.PIPE_CREATED   // stderr
    toit_exe
    [toit_exe, "tests/block_std_child.toit"]

  subprocess_stdout := subprocess[1]
  subprocess_stderr := subprocess[2]
  pid := subprocess[3]

  // Get the stderr first even though the subproces is blocking on stdout.
  line := subprocess_stderr.read
  // If this gets the wrong message then the buffer on stdout is too big and we
  // need to increase the size of the loop in block_std_child.toit.
  expect_equals "Message through stderr." line.to_string
  print "$line.to_string"
  task::
    while read := subprocess_stdout.read:
      null
  line = subprocess_stderr.read
  expect_equals "Done with stdout." line.to_string
  print "$line.to_string"

  exit_value := pipe.wait_for pid
  expect_equals 0
    pipe.exit_code exit_value
  expect_equals null
    pipe.exit_signal exit_value
  print "OK exit"
