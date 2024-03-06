// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import host.directory
import host.file
import host.pipe
import system
import bytes

CONTENT ::= "asdsssa"
main:
  // Make a temporary directory in the current directory.
  tmp-dir := directory.mkdtemp "/tmp/foo-"
  expect (file.is-directory tmp-dir)

  directory.chdir tmp-dir
  file.write-content CONTENT --path="test-file"
  expect-equals CONTENT.to-byte-array (file.read-content "test-file")
  directory.mkdir "test-dir"

  try:
    file.link --hard --source="test-file-hard-link" --target="test-file"
    expect-equals true (file.is-file "test-file-hard-link")
    file.link --file --source="test-file-soft-link" --target="test-file"
    expect-equals "test-file" (file.readlink "test-file-soft-link")
    file.link --source="test-dir-soft-link" --target="test-dir"
    expect-equals "test-dir" (file.readlink "test-dir-soft-link")


    file-stat := file.stat "test-file"
    expect-equals file-stat (file.stat "test-file-hard-link")
    expect-equals file-stat (file.stat "test-file-soft-link")
    expect-equals file-stat (file.stat --follow-links=false "test-file-hard-link")
    expect-not-equals file-stat (file.stat --follow-links=false "test-file-soft-link")

    dir-stat := file.stat "test-dir"
    expect-equals dir-stat (file.stat "test-dir-soft-link")
    expect-not-equals dir-stat (file.stat --follow-links=false "test-dir-soft-link")

    expect-equals CONTENT.to-byte-array (file.read-content "test-file-hard-link")
    expect-equals CONTENT.to-byte-array (file.read-content "test-file-soft-link")

    // Test that we can't auto detect link type if the target does not exist.
    expect-throw "TARGET_NOT_FOUND": file.link --source="test-file" --target="test-file-that-does-not-exist"

    // Test that we can't make a hard link to a directory.
    expect-throw "PERMISSION_DENIED": file.link --hard --source="hard-link-to-dir" --target="test-dir"

    // Test that relative soft-links are relative to the source.
    file.link --file --source="test-dir/relative" --target="relative-soft-name"
    expect-equals "relative-soft-name" (file.readlink "test-dir/relative")
    file.link --file --source="test-dir/relative-soft-name" --target="..$(directory.SEPARATOR)test-file"
    expect-equals "..$(directory.SEPARATOR)test-file" (file.readlink "test-dir/relative-soft-name")
    expect-equals CONTENT.to-byte-array (file.read-content "test-dir/relative")

    // Test that hardlinks are always relative to cwd.
    file.link --hard --source="test-dir/relative-hard" --target="test-file"
    expect-equals CONTENT.to-byte-array (file.read-content "test-dir/relative-hard")

    // Test that hard-links behaves as hard-link and soft-link behaves as soft-links.
    file.delete "test-file"
    expect-equals CONTENT.to-byte-array (file.read-content "test-file-hard-link")
    expect-throw "FILE_NOT_FOUND: \"test-file-soft-link\"" : file.read-content "test-file-soft-link"

    new-content := "new-content".to-byte-array
    file.write-content new-content --path="test-file"

    // Test relative links that isn't relative to the current directory.
    subdir := "$tmp-dir/subdir"
    directory.mkdir subdir
    file.link --file --source="$subdir/relative-link" --target="../test-file"
    expect-equals new-content (file.read-content "$subdir/relative-link")
    file.link --source="$subdir/relative-link2" --target="../test-file"
    expect-equals new-content (file.read-content "$subdir/relative-link2")

    // Same for directories.
    file.link --directory --source="$subdir/relative-dir-link" --target=".."
    expect-equals new-content (file.read-content "$subdir/relative-dir-link/test-file")
    file.link --source="$subdir/relative-dir-link2" --target=".."
    expect-equals new-content (file.read-content "$subdir/relative-dir-link2/test-file")

  finally:
    directory.rmdir tmp-dir --recursive
