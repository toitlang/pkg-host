// Copyright (C) 2020 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import host.directory
import host.file

main:
  // Make a temporary directory in the current dir.
  tmp-dir := directory.mkdtemp "foo-"
  expect (file.is-directory tmp-dir)

  directory.chdir tmp-dir
  // Make a regular directory in the current dir.
  // We would like to use directory.mkdtemp, but that doesn't work with
  //   relative paths after a chdir.
  tmp-dir2 := "bar-xxx"
  directory.mkdir tmp-dir2

  directory.chdir ".."

  dir := directory.DirectoryStream tmp-dir
  bar-name := dir.next
  expect
      bar-name.starts-with "bar-"

  directory.rmdir "$tmp-dir/$tmp-dir2"
  directory.rmdir tmp-dir

  // Make a temporary directory in the system dir.
  tmp-dir = directory.mkdtemp "/tmp/foo-"
  expect (file.is-directory tmp-dir)
  directory.rmdir tmp-dir
