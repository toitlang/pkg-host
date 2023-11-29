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
  // Make a temporary directory in the current dir.
  tmp_dir := directory.mkdtemp "/tmp/foo-"
  expect (file.is_directory tmp_dir)

  directory.chdir tmp_dir
  file.write_content CONTENT --path="test-file"
  expect-equals CONTENT.to_byte_array (file.read_content "test-file")
  directory.mkdir "test-dir"

  try:
    file.link --hard --source="test-file-hard-link" --target="test-file"
    expect-equals true (file.is_file "test-file-hard-link")
    file.link --soft --source="test-file-soft-link" --target="test-file"
    expect-equals "test-file" (file.readlink "test-file-soft-link")
    file.link --source="test-dir-soft-link" --target="test-dir"
    expect-equals "test-dir" (file.readlink "test-dir-soft-link")


    file_stat := file.stat "test-file"
    expect-equals file_stat (file.stat "test-file-hard-link")
    expect-equals file_stat (file.stat "test-file-soft-link")
    expect-equals file_stat (file.stat --follow_links=false "test-file-hard-link")
    expect-not-equals file_stat (file.stat --follow_links=false "test-file-soft-link")

    dir_stat := file.stat "test-dir"
    expect-equals dir_stat (file.stat "test-dir-soft-link")
    expect-not-equals dir_stat (file.stat --follow_links=false "test-dir-soft-link")

    expect-equals CONTENT.to_byte_array (file.read_content "test-file-hard-link")
    expect-equals CONTENT.to_byte_array (file.read_content "test-file-soft-link")

    // Test that relative soft-links are relative to the source
    file.link --soft --source="test-dir/relative" --target="relative-soft-name"
    expect-equals "relative-soft-name" (file.readlink "test-dir/relative")
    file.link --soft --source="test-dir/relative-soft-name" --target="..$(directory.dir-separator)test-file"
    expect-equals "..$(directory.dir-separator)test-file" (file.readlink "test-dir/relative-soft-name")
    expect-equals CONTENT.to_byte_array (file.read_content "test-dir/relative")

    // Test that hardlinks are always relative to cwd
    file.link --hard --source="test-dir/relative-hard" --target="test-file"
    expect-equals CONTENT.to_byte_array (file.read_content "test-dir/relative-hard")

    // Test that hard-links behaves as hard-link and soft-link behaves as soft-links
    file.delete "test-file"
    expect-equals CONTENT.to_byte_array (file.read_content "test-file-hard-link")
    expect-throw "FILE_NOT_FOUND: \"test-file-soft-link\"" : file.read_content "test-file-soft-link"
  finally:
    directory.rmdir tmp_dir --recursive
