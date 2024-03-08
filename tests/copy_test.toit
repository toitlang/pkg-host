// Copyright (C) 2024 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import host.file
import host.directory
import system show platform PLATFORM-WINDOWS PLATFORM-LINUX PLATFORM-MACOS

with-tmp-dir [block]:
  tmp-dir := directory.mkdtemp "/tmp/copy-test-"
  try:
    block.call tmp-dir
  finally:
    directory.rmdir --force --recursive tmp-dir

main:
  test-recursive
  test-permissions
  test-symlinks

test-recursive:
  with-tmp-dir: | tmp-dir |
    tmp-file := "$tmp-dir/file.txt"
    directory.chdir tmp-dir

    content := "foobar".to-byte-array
    other-content := "gee".to-byte-array
    file.write-content --path=tmp-file content

    // Copy absolute path to absolute target path.
    file2 := "$tmp-dir/file2.txt"
    file.copy --source=tmp-file --target=file2
    expect-equals content (file.read-content file2)

    // Copy of relative file to relative directory path.
    directory.mkdir "subdir2"
    file.copy --source="file.txt" --target="subdir2/file.txt"
    expect-equals content (file.read-content "subdir2/file.txt")
    expect-equals content (file.read-content "$tmp-dir/subdir2/file.txt")

    // Copy recursive.
    directory.mkdir "subdir2/nested-subdir"
    file.write-content --path="subdir2/nested-subdir/other.txt" other-content
    file.copy --source="subdir2" --target="subdir3" --recursive
    expect-equals content (file.read-content "subdir3/file.txt")
    expect-equals other-content (file.read-content "subdir3/nested-subdir/other.txt")

    // Copy recursive to existing directory.
    directory.mkdir "subdir4"
    file.copy --source="subdir3" --target="subdir4" --recursive
    expect-equals content (file.read-content "subdir4/file.txt")
    expect-equals other-content (file.read-content "subdir4/nested-subdir/other.txt")

test-permissions:
  file-permission0/int := ?
  file-permission1/int := ?
  dir-permission/int := ?
  read-only-dir-permission/int := ?
  if platform == PLATFORM-WINDOWS:
    file-permission0 = file.WINDOWS-FILE-ATTRIBUTE-HIDDEN | file.WINDOWS-FILE-ATTRIBUTE-NORMAL
    file-permission1 = file.WINDOWS-FILE-ATTRIBUTE-READONLY | file.WINDOWS-FILE-ATTRIBUTE-NORMAL
    dir-permission = 0
    read-only-dir-permission = file.WINDOWS-FILE-ATTRIBUTE-READONLY
  else:
    file-permission0 = 0b111_000_000
    file-permission1 = 0b100_000_000
    dir-permission = 0b111_000_000
    read-only-dir-permission = 0b101_000_000

  with-tmp-dir: | tmp-dir |
    file1 := "$tmp-dir/file1.txt"
    file.write-content --path=file1 "foobar"

    file.chmod file1 file-permission0
    file.copy --source=file1 --target="$tmp-dir/file2.txt"
    expect-equals file-permission0 (file.stat "$tmp-dir/file2.txt")[file.ST-MODE]

    file.chmod file1 file-permission1
    file.copy --source=file1 --target="$tmp-dir/file3.txt"
    expect-equals file-permission1 (file.stat "$tmp-dir/file3.txt")[file.ST-MODE]

    dir := "$tmp-dir/dir"
    directory.mkdir dir

    file-in-dir := "$tmp-dir/dir/file.txt"
    file.write-content --path=file-in-dir "gee"

    file.chmod dir dir-permission
    file.copy --source=dir --target="$tmp-dir/dir2" --recursive
    expect-equals dir-permission (file.stat "$tmp-dir/dir2")[file.ST-MODE]
    expect-equals "gee".to-byte-array (file.read-content "$tmp-dir/dir2/file.txt")

    // Note that the directory doesn't allow writing.
    // This means that the copy operation must temporarily lift that restriction to copy the
    // nested file.
    file.chmod dir read-only-dir-permission
    file.copy --source=dir --target="$tmp-dir/dir3" --recursive
    expect-equals read-only-dir-permission (file.stat "$tmp-dir/dir3")[file.ST-MODE]
    expect-equals "gee".to-byte-array (file.read-content "$tmp-dir/dir2/file.txt")

test-symlinks:
  with-tmp-dir: | tmp-dir |
    file-target := "$tmp-dir/file.txt"
    file-content := "foobar".to-byte-array
    file.write-content --path=file-target file-content
    dir-target := "$tmp-dir/dir"
    directory.mkdir dir-target
    dir-file := "$dir-target/file.txt"
    dir-file-content := "gee".to-byte-array
    file.write-content --path=dir-file dir-file-content

    source-dir := "$tmp-dir/source"
    directory.mkdir source-dir

    relative-link := "$source-dir/relative-link"
    absolute-link := "$source-dir/absolute-link"
    file.link --file --source="$source-dir/relative-link" --target="../file.txt"
    file.link --file --source="$source-dir/absolute-link" --target="$tmp-dir/file.txt"
    file.link --directory --source="$source-dir/relative-dir" --target="../dir"
    file.link --directory --source="$source-dir/absolute-dir" --target="$tmp-dir/dir"

    copy-target := "$tmp-dir/copy-target-symlink"
    file.copy --source=source-dir --target=copy-target --recursive
    expect-equals file-content (file.read-content "$copy-target/relative-link")
    expect-equals file-content (file.read-content "$copy-target/absolute-link")
    // Change the original file.
    // Since the copy is still a link we expect the content to change.
    file-content2 := "foobar2".to-byte-array
    file.write-content --path=file-target file-content2
    expect-equals file-content2 (file.read-content "$copy-target/relative-link")
    expect-equals file-content2 (file.read-content "$copy-target/absolute-link")
    expect (is-link "$copy-target/relative-link")
    expect (is-link "$copy-target/absolute-link")

    expect-equals dir-file-content (file.read-content "$copy-target/relative-dir/file.txt")
    expect-equals dir-file-content (file.read-content "$copy-target/absolute-dir/file.txt")
    // Change the original file.
    // Since the copy is still a link we expect the content to change.
    dir-file-content2 := "gee2".to-byte-array
    file.write-content --path=dir-file dir-file-content2
    expect-equals dir-file-content2 (file.read-content "$copy-target/relative-dir/file.txt")
    expect-equals dir-file-content2 (file.read-content "$copy-target/absolute-dir/file.txt")
    expect (is-link "$copy-target/relative-dir")
    expect (is-link "$copy-target/absolute-dir")

    // Dereference links.
    copy-target = "$tmp-dir/copy-target-dereference"

    file.copy --source=source-dir --target=copy-target --recursive --dereference
    expect-equals file-content2 (file.read-content "$copy-target/relative-link")
    expect-equals file-content2 (file.read-content "$copy-target/absolute-link")
    expect-not (is-link "$copy-target/relative-link")
    expect-not (is-link "$copy-target/absolute-link")

    expect-equals dir-file-content2 (file.read-content "$copy-target/relative-dir/file.txt")
    expect-equals dir-file-content2 (file.read-content "$copy-target/absolute-dir/file.txt")
    expect-not (is-link "$copy-target/relative-dir")
    expect-not (is-link "$copy-target/absolute-dir")

    // Copy the directory to a differently nested directory.
    // This means that relative links don't work anymore.
    directory.mkdir "$tmp-dir/other"
    copy-target = "$tmp-dir/other/copy-target"
    file.copy --source=source-dir --target=copy-target --recursive

    // Absolute links still work.
    expect-equals file-content2 (file.read-content "$copy-target/absolute-link")
    expect (is-link "$copy-target/absolute-link")
    expect-equals dir-file-content2 (file.read-content "$copy-target/absolute-dir/file.txt")
    expect (is-link "$copy-target/absolute-dir")

    expect-throws: file.read-content "$copy-target/relative-link"
    expect (is-link "$copy-target/relative-link")
    expect-throws: file.read-content "$copy-target/relative-dir/file.txt"
    expect (is-link "$copy-target/relative-dir")

    // Create the target.
    file.write-content --path="$tmp-dir/other/file.txt" file-content
    directory.mkdir "$tmp-dir/other/dir"
    file.write-content --path="$tmp-dir/other/dir/file.txt" dir-file-content
    // Now the symlinks work again.
    expect-equals file-content (file.read-content "$copy-target/relative-link")
    expect-equals dir-file-content (file.read-content "$copy-target/relative-dir/file.txt")

is-link path/string -> bool:
  stat := file.stat path --no-follow-links
  type := stat[file.ST-TYPE]
  return type == file.SYMBOLIC-LINK or type == file.DIRECTORY-SYMBOLIC-LINK

expect-throws [block]:
  exception := catch block
  expect-not-null exception
