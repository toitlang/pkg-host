// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import system

import host.file
import host.directory show *

with_tmp_dir [block]:
  tmp_dir := mkdtemp
  try:
    block.call tmp_dir
  finally:
    rmdir --recursive tmp_dir

main:
  with_tmp_dir: | tmp_dir |
    ["test-foo", "test-føo", "test-f€o", "test-f😀o"].do: | name |
      // Create relative directory in the current working directory.
      // Pollutes the current working directory, but we want to test
      // relative directory creation.
      print "Make $name"
      mkdir name
      expect (file.is_directory name)
      print "Remove name"
      rmdir name
      expect_not (file.is_directory name)

      tmp_name := "$tmp_dir/$name"
      print "Make $tmp_name"
      mkdir tmp_name
      expect (file.is_directory tmp_name)
      print "Remove $tmp_dir/name"
      rmdir tmp_name
      expect_not (file.is_directory name)

    mkdir --recursive "test-foo/bar/gee"
    expect (file.is_directory "test-foo/bar/gee")
    rmdir --recursive "test-foo"
    expect_not (file.is_directory "test-foo")

    mkdir --recursive "$tmp_dir/test-foo/bar/gee"
    expect (file.is_directory "$tmp_dir/test-foo/bar/gee")
    rmdir --recursive "$tmp_dir/test-foo"
    expect_not (file.is_directory "$tmp_dir/test-foo")

    if system.platform == system.PLATFORM-WINDOWS:
      mkdir --recursive "test-foo\\bar\\gee"
      expect (file.is_directory "test-foo\\bar\\gee")
      rmdir --recursive "test-foo"
      expect_not (file.is_directory "test-foo")

      mkdir --recursive "$tmp_dir\\test-foo\\bar\\gee"
      expect (file.is_directory "$tmp_dir\\test-foo\\bar\\gee")
      rmdir --recursive "$tmp_dir\\test-foo"
      expect_not (file.is_directory "$tmp_dir\\test-foo")
