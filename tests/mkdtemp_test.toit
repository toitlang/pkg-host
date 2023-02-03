// Copyright (C) 2020 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import expect show *
import host.directory
import host.file

main:
  // Make a temporary directory in the current dir.
  tmp_dir := directory.mkdtemp "foo-"
  expect (file.is_directory tmp_dir)

  directory.chdir tmp_dir
  // Make a temporary directory in the current dir.
  tmp_dir2 := directory.mkdtemp "bar-"

  directory.chdir ".."

  dir := directory.DirectoryStream tmp_dir
  bar_name := dir.next
  expect
      bar_name.starts_with "bar-"

  directory.rmdir tmp_dir2
  directory.rmdir tmp_dir

  // Make a temporary directory in the system dir.
  tmp_dir = directory.mkdtemp "/tmp/foo-"
  expect (file.is_directory tmp_dir)
  directory.rmdir tmp_dir
