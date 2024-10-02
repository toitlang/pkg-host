// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import system

import host.file
import host.directory show *

with-tmp-dir [block]:
  tmp-dir := mkdtemp "/tmp/mkdir-rmdir-test-"
  try:
    block.call tmp-dir
  finally:
    rmdir --recursive --force tmp-dir

main:
  with-tmp-dir: | tmp-dir |
    chdir tmp-dir

    ["test-foo", "test-føo", "test-f€o", "test-f😀o"].do: | name |
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

    // Test permissions.
    dir0 := "$tmp-dir/perm0"
    mkdir dir0
    file.write-contents --path="$dir0/file1" "content"
    dir1 := "$dir0/perm1"
    mkdir dir1
    file.write-contents --path="$dir1/file" "content"

    old-stat0 := file.stat dir0
    old-stat1 := file.stat dir1
    if system.platform == system.PLATFORM-WINDOWS:
      new-permissions := file.WINDOWS-FILE-ATTRIBUTE-READONLY | file.WINDOWS-FILE-ATTRIBUTE-READONLY
      file.chmod dir1 new-permissions
    else:
      new-permissions := 0b000_000_000
      file.chmod dir1 new-permissions

    exception := catch:
      rmdir dir0 --recursive
    expect-not-null exception

    rmdir dir0 --recursive --force

    // Test symbolic link.
    sym-file-target := "$tmp-dir/sym-file-target"
    sym-dir-target := "$tmp-dir/sym-dir-target"
    file.write-contents --path=sym-file-target "content"
    mkdir sym-dir-target

    sub-dir := "$tmp-dir/sub-dir"
    mkdir sub-dir
    file.link --source="$sub-dir/sym-file" --target=sym-file-target
    file.link --source="$sub-dir/sym-dir" --target=sym-dir-target
    rmdir --recursive sub-dir
    // Neither the file nor the directory should be removed.
    expect (file.is-file sym-file-target)
    expect (file.is-directory sym-dir-target)
