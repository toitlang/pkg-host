// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import expect show *

import host.pipe
import host.directory
import semver

main args:
  if args[0] == "--run-test":
    test-not-existing
    return

  toit-run := args[0]
  test-not-existing

  5.repeat:
    pipe.run-program toit-run "tests/dir_test.toit" "--run-test"

test-not-existing:
  50.repeat:
    exception := catch:
      files := directory.DirectoryStream "not-existing"
      unreachable
    expect-not-null exception
