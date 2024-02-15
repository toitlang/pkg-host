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

  toit-exe := args[0]

  version/string? := null

  // Try to run the toit executable.
  exception := catch: version = pipe.backticks toit-exe "--version"
  if exception:
    print "Running the given toit executable '$toit-exe' failed: $exception"
    exit 1

  print version
