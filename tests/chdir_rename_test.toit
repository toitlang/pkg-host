// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import host.file
import host.directory show *
import writer show Writer

expect_ name [code]:
  exception := catch code
  if not exception.starts-with name:
    print "Expected something that starts with $name but got $exception"
  expect
    exception.starts-with name

expect-file-not-found [code]:
  expect_ "FILE_NOT_FOUND" code

main:
  expect-file-not-found: chdir "non_existing_dir"
  if file.is-file "/etc/resolv.conf":
    expect-file-not-found: chdir "/etc/resolv.conf"
  if file.is-file "C:/Windows/System32/cmd.exe":
    expect-file-not-found: chdir "C:/Windows/System32/cmd.exe"

  random-name := "test_dir_$(random 1_000_000_000)"
  new-name := "test_dir_$(random 1_000_000_000)"
  mkdir random-name
  chdir random-name
  file.rename "../$random-name" "../$new-name"
  chdir ".."
  rmdir new-name
