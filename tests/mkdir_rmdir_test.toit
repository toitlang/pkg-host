// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import host.file
import host.directory show *
import writer show Writer

expect_ name [code]:
  expect
    (catch code).starts_with name

expect_out_of_bounds [code]:
  expect_ "OUT_OF_BOUNDS" code

expect_file_not_found [code]:
  expect_ "FILE_NOT_FOUND" code

expect_invalid_argument [code]:
  expect_ "INVALID_ARGUMENT" code

expect_already_closed [code]:
  expect_ "ALREADY_CLOSED" code

main:
  ["foo", "føo", "f€o", "f😀o"].do: | name |
    print "Make $name"
    mkdir name
    print "Remove $name"
    rmdir name
