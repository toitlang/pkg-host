// Copyright (C) 2025 Toit contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import host.directory
import host.pipe

check-toit-exe toit-exe/string:
  // Try to run the toit executable.
  print "Trying to run $toit-exe"
  exception := catch: pipe.backticks toit-exe "--version"
  if exception:
    print "Running the given toit executable '$toit-exe' failed: $exception"
    exit 1

  print "Managed to run $toit-exe"


with-tmp-dir prefix="/tmp/test" [block]:
  dir := directory.mkdtemp prefix
  try:
    block.call dir
  finally:
    directory.rmdir --recursive --force dir

with-compiled --toit-exe/string source/string [block]:
  with-tmp-dir: | dir/string |
    compiled-path := "$dir/out.exe"

    exit-value := pipe.run-program [toit-exe, "compile", "-o", compiled-path, source]
    if exit-value != 0:
      throw "Failed to create exe: $exit-value"

    block.call compiled-path
