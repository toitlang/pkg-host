// Copyright (C) 2020 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import host.directory
import host.file

main:
  // Make a temporary directory in the current dir.
  tmp_dir := directory.mkdtemp "foo-"
  expect (file.is_directory tmp_dir)

  directory.chdir tmp_dir
  // Make a regular directory in the current dir.
  // We would like to use directory.mkdtemp, but that doesn't work with
  //   relative paths after a chdir.
  tmp_dir2 := "bar-xxx"
  directory.mkdir tmp_dir2

  directory.chdir ".."

  dir := directory.DirectoryStream tmp_dir
  bar_name := dir.next
  expect
      bar_name.starts_with "bar-"

  directory.rmdir "$tmp_dir/$tmp_dir2"
  directory.rmdir tmp_dir

  // Make a temporary directory in the system dir.
  tmp_dir = directory.mkdtemp "/tmp/foo-"
  expect (file.is_directory tmp_dir)
  directory.rmdir tmp_dir
