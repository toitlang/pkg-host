// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import host.file
import host.directory
import system

import .utils

IS-WINDOWS ::= system.platform == system.PLATFORM-WINDOWS

TIME-SLACK ::= Duration --ms=3
expect-in-between-time a/Time b/Time c/Time:
  // We have seen cases where the mtime is before the "before"
  // time. Since the resolution of filesystems isn't guaranteed
  // anyway, just give some slack.
  slack := Duration --ms=3
  expect a - slack <= b <= c + slack

FS-SLACK ::= IS-WINDOWS
    ? Duration --ns=200  // Windows FILETIME is in 100ns increments.
    : Duration.ZERO
expect-fs-equals a/Time b/Time:
  expect (a.to b).abs <= FS-SLACK

check-atime [block]:
  // Windows has a really poor atime handling:
  // From their docs:
  // Not all file systems can record creation and last access times and not
  // all file systems record them in the same manner. For example, on FAT,
  // create time has a resolution of 10 milliseconds, write time has a
  // resolution of 2 seconds, and access time has a resolution of 1 day
  // (really, the access date). Therefore, the GetFileTime function may not
  // return the same file time information set using SetFileTime. NTFS delays
  // updates to the last access time for a file by up to one hour after the
  // last access.
  if IS-WINDOWS: return
  block.call

main:
  with-tmp-dir: | dir/string |
   e := catch --trace:
    test-file := "$dir/test.txt"
    test test-file
      --create=: file.write-contents --path=it "foo"
      --update-access=: file.read-contents it
      --update-modification=: file.write-contents --path=it "bar"

    test-dir := "$dir/test"
    test test-dir
      --create=:
        directory.mkdir it
      --update-access=:
        dir-stream := directory.DirectoryStream it
        while dir-stream.next: null
        dir-stream.close
      --update-modification=:
        file.write-contents --path="$it/inner" "bar"

test test-path/string
    [--create]
    [--update-access]
    [--update-modification]:
  expect-throw "FILE_NOT_FOUND": file.update-time test-path --access=Time.now

  before := Time.now
  create.call test-path
  stat-result := file.stat test-path
  atime := stat-result[file.ST-ATIME]
  mtime := stat-result[file.ST-MTIME]
  ctime := stat-result[file.ST-CTIME]
  sleep --ms=10
  after := Time.now
  check-atime:
    expect-in-between-time before atime after
  expect-in-between-time before mtime after
  expect-in-between-time before ctime after
  update-time := Time.now

  // Update the atime.
  // With mount-option "relatime" (most commonly used nowadays), the
  // atime should be guaranteed to be greater than mtime now.
  update-access.call test-path
  stat-result = file.stat test-path
  atime = stat-result[file.ST-ATIME]
  mtime = stat-result[file.ST-MTIME]
  expect atime >= mtime

  // Update the access time.
  file.update-time test-path --access=update-time
  stat-result = file.stat test-path
  atime = stat-result[file.ST-ATIME]
  unchanged-mtime := stat-result[file.ST-MTIME]
  check-atime: expect-fs-equals update-time atime
  expect-fs-equals mtime unchanged-mtime

  before = Time.now
  update-modification.call test-path
  after = Time.now
  stat-result = file.stat test-path
  atime = stat-result[file.ST-ATIME]
  mtime = stat-result[file.ST-MTIME]
  check-atime: expect-in-between-time before atime after
  expect-in-between-time before mtime after

  // Update the modification time.
  update-time2 := Time.now
  file.update-time test-path --modification=update-time2
  stat-result = file.stat test-path
  atime = stat-result[file.ST-ATIME]
  mtime = stat-result[file.ST-MTIME]
  check-atime: expect-fs-equals update-time atime
  expect-fs-equals update-time2 mtime

  // Update both times.
  update-time = Time.now
  update-time2 = Time.now

  file.update-time test-path --access=update-time --modification=update-time2
  stat-result = file.stat test-path
  atime = stat-result[file.ST-ATIME]
  mtime = stat-result[file.ST-MTIME]
  check-atime: expect-fs-equals update-time atime
  expect-fs-equals update-time2 mtime
