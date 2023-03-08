// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import expect show *

import host.file
import host.directory show *
import writer show Writer

expect_ name [code]:
  exception := catch code
  if not exception.starts_with name:
    print "Expected something that starts with $name but got $exception"
  expect
    exception.starts_with name

expect_file_not_found [code]:
  expect_ "FILE_NOT_FOUND" code

main:
  expect_file_not_found: chdir "non_existing_dir"
  if file.is_file "/etc/resolv.conf":
    expect_file_not_found: chdir "/etc/resolv.conf"
  if file.is_file "C:/Windows/System32/cmd.exe":
    expect_file_not_found: chdir "C:/Windows/System32/cmd.exe"

  random_name := "test_dir_$(random 1_000_000_000)"
  new_name := "test_dir_$(random 1_000_000_000)"
  mkdir random_name
  chdir random_name
  file.rename "../$random_name" "../$new_name"
  chdir ".."
  rmdir new_name
