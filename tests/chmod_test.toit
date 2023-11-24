// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import host.directory
import host.file
import host.pipe
import system

main:
  // Make a temporary directory in the current dir.
  tmp_dir := directory.mkdtemp "/tmp/foo-"
  expect (file.is_directory tmp_dir)

  directory.chdir tmp_dir
  file.write_content "asdsd" --path="test"
  try:
    if system.platform == system.PLATFORM_WINDOWS:
      file.chmod "test" file.WINDOWS-FILE-ATTRIBUTE-READONLY
      expect_equals file.WINDOWS-FILE-ATTRIBUTE-READONLY (file.stat "test")[file.ST_MODE]

      file.chmod "test" file.WINDOWS-FILE-ATTRIBUTE-NORMAL
      expect_equals file.WINDOWS-FILE-ATTRIBUTE-NORMAL (file.stat "test")[file.ST_MODE]

      file.chmod "test" file.WINDOWS-FILE-ATTRIBUTE-ARCHIVE
      expect_equals file.WINDOWS-FILE-ATTRIBUTE-ARCHIVE (file.stat "test")[file.ST_MODE]

      file.chmod "test" file.WINDOWS-FILE-ATTRIBUTE-HIDDEN
      expect_equals file.WINDOWS-FILE-ATTRIBUTE-HIDDEN (file.stat "test")[file.ST_MODE]

      file.chmod "test" file.WINDOWS-FILE-ATTRIBUTE-SYSTEM
      expect_equals file.WINDOWS-FILE-ATTRIBUTE-SYSTEM (file.stat "test")[file.ST_MODE]
    else:
      file.chmod "test" 0b100100100
      expect_equals 0b100100100 (file.stat "test")[file.ST_MODE]
      file.chmod "test" 0b100000000
      expect_equals 0b100000000 (file.stat "test")[file.ST_MODE]
      file.chmod "test" 0b110000000
      expect_equals 0b110000000 (file.stat "test")[file.ST_MODE]
  finally:
    directory.rmdir tmp_dir --recursive