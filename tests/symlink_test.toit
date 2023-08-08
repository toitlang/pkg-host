// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import host.file
import host.directory
import host.pipe
import host.os

tool_path_ tool/string -> string:
  if platform != PLATFORM_WINDOWS: return tool
  // On Windows, we use the <tool>.exe that comes with Git for Windows.

  // TODO(florian): depending on environment variables is brittle.
  // We should use `SearchPath` (to find `git.exe` in the PATH), or
  // 'SHGetSpecialFolderPath' (to find the default 'Program Files' folder).
  program_files_path := os.env.get "ProgramFiles"
  if not program_files_path:
    // This is brittle, as Windows localizes the name of the folder.
    program_files_path = "C:/Program Files"
  result := "$program_files_path/Git/usr/bin/$(tool).exe"
  if not file.is_file result:
    throw "Could not find $result. Please install Git for Windows"
  return result

/**
Extracts the contents of a tar file at $path to the given $to directory.
*/
extract_tar --to/string path/string:
    tar := tool_path_ "tar"

    extra_args := []
    if platform == PLATFORM_WINDOWS:
      // Tar can't handle backslashes as separators.
      path = path.replace --all "\\" "/"
      to = to.replace --all "\\" "/"
      extra_args = ["--force-local"]

    pipe.run_program [tar, "x", "-f", path, "-C", to] + extra_args

with_tmp_directory [block]:
  tmpdir := directory.mkdtemp "/tmp/host-test-"
  try:
    block.call tmpdir
  finally:
    directory.rmdir --recursive tmpdir

SYMLINK_TAR_FILE ::= "tests/symlink_test.tar"

main:
  with_tmp_directory: | tmp_dir |
    extract_tar SYMLINK_TAR_FILE --to=tmp_dir

    /*
    Check that the tar is what we expect it to be:
        ᐅ ls -l "symlink_test/"*
        symlink_test/a:
        total 0
        lrwxrwxrwx 1 flo flo 4 Aug  8 17:07 sym_b -> ../b

        symlink_test/b:
        total 0
        -rw-r--r-- 1 flo flo 0 Aug  8 17:06 foo.txt
    */
    expect (file.is_directory "$tmp_dir/symlink_test/a")
    expect (file.is_directory "$tmp_dir/symlink_test/b")
    expect (file.is_directory "$tmp_dir/symlink_test/a/sym_b" --follow_links)
    if platform != PLATFORM_WINDOWS:
      // Git bash can support symlinks, but they need to be enabled in a configuration.
      // The Github builders seem to have them disabled.
      expect_not (file.is_directory "$tmp_dir/symlink_test/a/sym_b" --no-follow_links)

    // Recursive rmdir should not follow symlinks.
    directory.rmdir --recursive "$tmp_dir/symlink_test/a"
    expect_not (file.is_directory "$tmp_dir/symlink_test/a")
    expect (file.is_directory "$tmp_dir/symlink_test/b")
    expect (file.is_file "$tmp_dir/symlink_test/b/foo.txt")
