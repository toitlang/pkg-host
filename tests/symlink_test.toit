// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import host.file
import host.directory
import host.pipe
import host.os
import system show platform PLATFORM-WINDOWS

tool-path_ tool/string -> string:
  if platform != PLATFORM-WINDOWS: return tool
  // On Windows, we use the <tool>.exe that comes with Git for Windows.

  // TODO(florian): depending on environment variables is brittle.
  // We should use `SearchPath` (to find `git.exe` in the PATH), or
  // 'SHGetSpecialFolderPath' (to find the default 'Program Files' folder).
  program-files-path := os.env.get "ProgramFiles"
  if not program-files-path:
    // This is brittle, as Windows localizes the name of the folder.
    program-files-path = "C:/Program Files"
  result := "$program-files-path/Git/usr/bin/$(tool).exe"
  if not file.is-file result:
    throw "Could not find $result. Please install Git for Windows"
  return result

/**
Extracts the contents of a tar file at $path to the given $to directory.
*/
extract-tar --to/string path/string:
    tar := tool-path_ "tar"

    extra-args := []
    if platform == PLATFORM-WINDOWS:
      // Tar can't handle backslashes as separators.
      path = path.replace --all "\\" "/"
      to = to.replace --all "\\" "/"
      extra-args = ["--force-local"]

    pipe.run-program [tar, "x", "-f", path, "-C", to] + extra-args

with-tmp-directory [block]:
  tmpdir := directory.mkdtemp "/tmp/host-test-"
  try:
    block.call tmpdir
  finally:
    directory.rmdir --recursive tmpdir

SYMLINK-TAR-FILE ::= "tests/symlink_test.tar"

main:
  with-tmp-directory: | tmp-dir |
    extract-tar SYMLINK-TAR-FILE --to=tmp-dir

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
    expect (file.is-directory "$tmp-dir/symlink_test/a")
    expect (file.is-directory "$tmp-dir/symlink_test/b")
    expect (file.is-directory "$tmp-dir/symlink_test/a/sym_b" --follow-links)
    if platform != PLATFORM-WINDOWS:
      // Git bash can support symlinks, but they need to be enabled in a configuration.
      // The Github builders seem to have them disabled.
      expect-not (file.is-directory "$tmp-dir/symlink_test/a/sym_b" --no-follow-links)

    // Recursive rmdir should not follow symlinks.
    directory.rmdir --recursive "$tmp-dir/symlink_test/a"
    expect-not (file.is-directory "$tmp-dir/symlink_test/a")
    expect (file.is-directory "$tmp-dir/symlink_test/b")
    expect (file.is-file "$tmp-dir/symlink_test/b/foo.txt")
