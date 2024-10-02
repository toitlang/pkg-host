// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import host.file
import host.directory show *
import system show platform PLATFORM-WINDOWS

expect_ name [code]:
  expect
    (catch code).starts-with name

expect-out-of-bounds [code]:
  expect_ "OUT_OF_BOUNDS" code

expect-file-not-found [code]:
  expect_ "FILE_NOT_FOUND" code

expect-invalid-argument [code]:
  expect_ "INVALID_ARGUMENT" code

expect-already-closed [code]:
  expect_ "ALREADY_CLOSED" code

main:
  expect-file-not-found: file.Stream.for-read "mkfxz.not_there"
  expect-file-not-found: file.Stream "mkfxz.not_there" file.RDONLY
  expect-invalid-argument: file.Stream "any name" file.CREAT       // Can't create a file without permissions.

  nul-device := (platform == PLATFORM-WINDOWS ? "\\\\.\\NUL" : "/dev/null")
  open-file := file.Stream.for-read nul-device
  byte-array := open-file.in.read
  expect (not byte-array)
  open-file.close
  expect-already-closed: open-file.close

  open-file = file.Stream nul-device file.RDONLY
  byte-array = open-file.in.read
  expect (not byte-array)
  open-file.close
  expect-already-closed: open-file.close

  test-contents := "This is the contents of the tæst file"

  tmpdir := mkdtemp "/tmp/toit_file_test_"

  try:

    test-recursive tmpdir
    test-cwd tmpdir
    test-realpath tmpdir

    chdir tmpdir

    test-recursive ""
    test-recursive "."

    filename := "test.out"
    dirname := "testdir"

    mkdir dirname

    try:
      test-out := file.Stream.for-write filename

      try:
        test-out.out.write test-contents
        test-out.out.close

        10000.repeat:
          file.read-contents filename

        read-back := (file.read-contents filename).to-string

        expect-equals test-contents read-back

        expect-equals test-contents.size (file.size filename)

      finally:
        file.delete filename

      test-out = file.Stream.for-write filename
      try:
        test-out.out.close
        expect-equals
          ByteArray 0
          file.read-contents filename
      finally:
        file.delete filename

      expect (not file.size filename)

      test-out = file.Stream.for-write filename

      try:
        from := 5
        to := 7
        test-out.out.write test-contents from to
        test-out.out.close

        read-back := (file.read-contents filename).to-string

        expect-equals (test-contents.copy from to) read-back

        expect-equals (to - from) (file.size filename)

      finally:
        file.delete filename

      expect (not file.size filename)

      try:
        file.write-contents test-contents --path=filename
        read-back := (file.read-contents filename).to-string
        expect-equals test-contents read-back
      finally:
        file.delete filename

      expect (not file.size filename)

      // Permissions does not quite work on windows
      if platform != PLATFORM-WINDOWS:
        try:
          file.write-contents test-contents --path=filename --permissions=(6 << 6)
          read-back := (file.read-contents filename).to-string
          expect-equals test-contents read-back
          stats := file.stat filename
          // We can't require that the permissions are exactly the same (as the umask
          // might clear some bits).
          expect-equals (6 << 6) ((6 << 6) | stats[file.ST-MODE])
        finally:
          file.delete filename

      expect (not file.size filename)

      cwd-path := cwd

      path-sep := platform == PLATFORM-WINDOWS ? "\\" : "/"

      chdir dirname
      expect-equals "$cwd-path$path-sep$dirname" cwd

      expect-equals "$cwd-path$path-sep$dirname" (realpath ".")
      expect-equals "$cwd-path" (realpath "..")
      expect-equals "$cwd-path$path-sep$dirname" (realpath "../$dirname")
      expect-equals "$cwd-path" (realpath "../$dirname/..")
      expect-equals null (realpath "fætter");

      test-out = file.Stream filename file.CREAT | file.WRONLY 0x1ff
      test-out.out.write test-contents
      test-out.out.close

      expect-equals test-contents.size (file.size filename)
      chdir ".."
      expect-equals test-contents.size (file.size "$dirname/$filename")

      dir := DirectoryStream dirname
      name := dir.next
      expect name == filename
      expect (not dir.next)
      dir.close
      dir.close  // We allow multiple calls to close.

      file.delete "$dirname/$filename"

    finally:
      rmdir dirname

  finally:
    rmdir tmpdir

test-recursive test-dir:
  // We want to test creation of paths if they are relative.
  rec-dir := test-dir == "" ? "rec" : "$test-dir/rec"

  deep-dir := "$rec-dir/a/b/c/d"
  mkdir --recursive deep-dir
  expect (file.is-directory deep-dir)

  paths := [
    "$rec-dir/foo",
    "$rec-dir/a/bar",
    "$rec-dir/a/b/gee",
    "$rec-dir/a/b/c/toto",
    "$rec-dir/a/b/c/d/titi",
  ]
  paths.do:
    stream := file.Stream.for-write it
    stream.out.write it
    stream.out.close

  paths.do:
    expect (file.is-file it)

  rmdir --recursive rec-dir
  expect (not file.stat rec-dir)

test-cwd test-dir:
  current-dir := cwd
  chdir test-dir
  expect-equals (realpath test-dir) (realpath cwd)
  chdir current-dir

test-realpath test-dir:
  current-dir := cwd
  // Use "realpath" when changing into the test-directory.
  // The directory might be a symlink.
  real-tmp := realpath test-dir
  chdir real-tmp
  expect-equals real-tmp (realpath ".")
  expect-equals real-tmp (realpath test-dir)
  chdir current-dir
