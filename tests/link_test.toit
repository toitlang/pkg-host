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
    expect-equals true ((file.readlink "test-file-soft-link").ends_with "test-file")
    file.link --source="test-dir-soft-link" --target="test-dir"
    expect-equals true ((file.readlink "test-dir-soft-link").ends_with "test-dir")

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

  finally:
    directory.rmdir tmp_dir --recursive
