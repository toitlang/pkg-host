// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import system

import host.file
import host.directory show *

with-tmp-dir [block]:
  tmp-dir := mkdtemp
  try:
    block.call tmp-dir
  finally:
    rmdir --recursive tmp-dir

main:
  with-tmp-dir: | tmp-dir |
    ["test-foo", "test-føo", "test-f€o", "test-f😀o"].do: | name |
      // Create relative directory in the current working directory.
      // Pollutes the current working directory, but we want to test
      // relative directory creation.
      print "Make $name"
      mkdir name
      expect (file.is-directory name)
      print "Remove name"
      rmdir name
      expect-not (file.is-directory name)

      tmp-name := "$tmp-dir/$name"
      print "Make $tmp-name"
      mkdir tmp-name
      expect (file.is-directory tmp-name)
      print "Remove $tmp-dir/name"
      rmdir tmp-name
      expect-not (file.is-directory name)

    mkdir --recursive "test-foo/bar/gee"
    expect (file.is-directory "test-foo/bar/gee")
    rmdir --recursive "test-foo"
    expect-not (file.is-directory "test-foo")

    mkdir --recursive "$tmp-dir/test-foo/bar/gee"
    expect (file.is-directory "$tmp-dir/test-foo/bar/gee")
    rmdir --recursive "$tmp-dir/test-foo"
    expect-not (file.is-directory "$tmp-dir/test-foo")

    if system.platform == system.PLATFORM-WINDOWS:
      mkdir --recursive "test-foo\\bar\\gee"
      expect (file.is-directory "test-foo\\bar\\gee")
      rmdir --recursive "test-foo"
      expect-not (file.is-directory "test-foo")

      mkdir --recursive "$tmp-dir\\test-foo\\bar\\gee"
      expect (file.is-directory "$tmp-dir\\test-foo\\bar\\gee")
      rmdir --recursive "$tmp-dir\\test-foo"
      expect-not (file.is-directory "$tmp-dir\\test-foo")
