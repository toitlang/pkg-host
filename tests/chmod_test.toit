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
  tmp-dir := directory.mkdtemp "/tmp/foo-"
  expect (file.is-directory tmp-dir)

  directory.chdir tmp-dir
  file.write-content "asdsd" --path="test"
  try:
    if system.platform == system.PLATFORM-WINDOWS:
      file.chmod "test" file.WINDOWS-FILE-ATTRIBUTE-READONLY
      expect-equals file.WINDOWS-FILE-ATTRIBUTE-READONLY (file.stat "test")[file.ST-MODE]

      file.chmod "test" file.WINDOWS-FILE-ATTRIBUTE-NORMAL
      expect-equals file.WINDOWS-FILE-ATTRIBUTE-NORMAL (file.stat "test")[file.ST-MODE]

      file.chmod "test" file.WINDOWS-FILE-ATTRIBUTE-ARCHIVE
      expect-equals file.WINDOWS-FILE-ATTRIBUTE-ARCHIVE (file.stat "test")[file.ST-MODE]

      file.chmod "test" file.WINDOWS-FILE-ATTRIBUTE-HIDDEN
      expect-equals file.WINDOWS-FILE-ATTRIBUTE-HIDDEN (file.stat "test")[file.ST-MODE]

      file.chmod "test" file.WINDOWS-FILE-ATTRIBUTE-SYSTEM
      expect-equals file.WINDOWS-FILE-ATTRIBUTE-SYSTEM (file.stat "test")[file.ST-MODE]
    else:
      file.chmod "test" 0b100_100_100
      expect-equals 0b100100100 (file.stat "test")[file.ST-MODE]
      file.chmod "test" 0b100_000_000
      expect-equals 0b100000000 (file.stat "test")[file.ST-MODE]
      file.chmod "test" 0b110_000_000
      expect-equals 0b110_000_000 (file.stat "test")[file.ST-MODE]
  finally:
    directory.rmdir tmp-dir --recursive
