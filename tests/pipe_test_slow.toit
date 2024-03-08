// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import host.directory show *
import host.file
import host.pipe
import system show platform PLATFORM-WINDOWS PLATFORM-LINUX PLATFORM-MACOS PLATFORM-FREERTOS

expect-error name [code]:
  expect-equals
    name
    catch code

expect-file-not-found cmd [code]:
  if (cmd.index-of " ") == -1:
    if platform == PLATFORM-WINDOWS:
      expect-error "Error trying to run '$cmd' using \$PATH: FILE_NOT_FOUND" code
    else:
      expect-error "Error trying to run '$cmd' using \$PATH: No such file or directory" code
  else:
    if platform == PLATFORM-WINDOWS:
      expect-error "Error trying to run executable (arguments appended to filename?): '$cmd': FILE_NOT_FOUND" code
    else:
      expect-error "Error trying to run executable (arguments appended to filename?): '$cmd': No such file or directory" code

if-windows windows unix:
  if platform == PLATFORM-WINDOWS: return windows
  return unix

low-level-test toit-exe:
  return
  // TODO: This is intended to test that we can have a different
  // program name to the name in arguments[0].  But it doesn't work on Windows
  // at the moment.  There was an implementation in
  // https://github.com/toitlang/toit/pull/1400, but it fails to find
  // executables without the explicit ".exe" extension, so it was annoying.
  INHERIT ::= pipe.PIPE-INHERITED
  output := pipe.OpenPipe false
  stdout := output.fd
  array := pipe.fork true INHERIT stdout INHERIT toit-exe ["ignored-0-argument", "tests/echo.toit", "horse"]
  expect-equals
    "horse"
    output.read.to-string.trim
  expect-equals
    null
    output.read

main args:
  if args.size < 1:
    print "Usage: pipe_test_slow.toit <toit_exe>"
    exit 1

  low-level-test args[0]

  // This test does not work on ESP32 since you can't launch subprocesses.
  if platform == PLATFORM-FREERTOS: return

  print " ** Some child processes will print errors on stderr during **"
  print " ** this test.  This is harmless and expected.              **"
  pipe-large-file
  write-closed-stdin-exception

  if file.is-file "/usr/bin/true":
    expect-equals
      0
      pipe.system "/usr/bin/true"

  simple-ls-command := if-windows "dir %ComSpec%" "ls /bin/sh"
  expect-equals
    0
    pipe.system
      simple-ls-command

  // run_program does not parse the command line, splitting at spaces, so it's
  // looking for a single program of the name "ls /bin/sh".
  expect-file-not-found simple-ls-command: pipe.run-program simple-ls-command

  // There's no such program as ll.
  expect-file-not-found "ll": pipe.run-program "ll" "/bin/sh"

  expect-equals
    0
    pipe.run-program "ls" "/bin/sh"

  // Increase the heap size a bit so that frequent GCs do not clean up file descriptors.
  a := []
  100.repeat:
    a.add "$it"

  // If backticks doesn't clean up open file descriptors, this will run out of
  // them.  Sadly, Windows is astonishingly slow at starting subprocesses.
  (platform == PLATFORM-WINDOWS ? 100 : 2000).repeat:
    expect-equals
      ""
      pipe.backticks "true"

  expect-equals
    "/bin/sh\n"
    pipe.backticks "ls" "/bin/sh"

  no-exist-cmd := "a program name that does not exist"
  expect-file-not-found no-exist-cmd : pipe.to no-exist-cmd

  tmpdir := mkdtemp "/tmp/toit_file_test_"
  old-current-directory := cwd

  try:
    chdir tmpdir

    filename := "test.out"
    dirname := "testdir"

    mkdir dirname
    go-up := false

    try:
      p := pipe.to "sh" "-c" "tr A-Z a-z > $dirname/$filename"
      p.write #[]  // Make sure we can deal with empty writes.
      p.write "The contents of the file"
      p.close

      expect (file.size "$dirname/$filename") != null

      chdir dirname
      go-up = true

      output := ""
      if platform == PLATFORM-WINDOWS:
        p = pipe.from "certutil" "-hashfile" filename
        while byte-array := p.read:
          output += byte-array.to-string

        expect output == "SHA1 hash of $filename:\r\n2dcc8e172c72f3d6937d49be7cf281067d257a62\r\nCertUtil: -hashfile command completed successfully.\r\n"
      else:
        p = pipe.from "shasum" filename
        while byte-array := p.read:
          output += byte-array.to-string

        expect output == "2dcc8e172c72f3d6937d49be7cf281067d257a62  $filename\n"

      chdir ".."
      go-up = false

    finally:
      if go-up:
        chdir ".."
      file.delete "$dirname/$filename"
      rmdir dirname

  finally:
    rmdir --recursive tmpdir

  chdir old-current-directory

  if platform == PLATFORM-WINDOWS:
    expect-error "certutil: exited with status 2":
      p := pipe.from "certutil" "file_that_doesn't exist"
      while p.read:
        // Do nothing.

    expect-error "certutil: exited with status 2":
      sum := pipe.backticks "certutil" "file_that_doesn't exist"
  else:
    expect-error "shasum: exited with status 1":
      p := pipe.from "shasum" "file_that_doesn't exist"
      while p.read:
        // Do nothing.

    expect-error "shasum: exited with status 1":
      sum := pipe.backticks "shasum" "file_that_doesn't exist"

  tar-exit-code := (platform == PLATFORM-LINUX) ? 2 : 1
  expect-error "tar: exited with status $tar-exit-code":
    p := pipe.to "tar" "-xvf" "-" "foo.txt"
    p.close  // Close without sending a valid tar file.

  task:: long-running-sleep

  // Exit explicitly - this will interrupt the task that is just waiting for
  // the subprocess to exit.
  exit 0

// Task that is interrupted by an explicit exit.
long-running-sleep:
  pipe.run-program "sleep" "1000"

/// Returns whether a path exists and is a character device.
is-char-device name --follow-links/bool=true -> bool:
  stat := file.stat name --follow-links
  if not stat: return false
  return stat[file.ST-TYPE] == file.CHARACTER-DEVICE

pipe-large-file:
  md5sum/string? := null
  if platform == PLATFORM-WINDOWS:
    GIT-MD5SUM := "c:/Program Files/Git/usr/bin/md5sum.exe"
    if file.is-file GIT-MD5SUM:
      md5sum = GIT-MD5SUM
  else if platform == PLATFORM-MACOS:
    md5sum = "md5"
  else:
    md5sum = "md5sum"
  if md5sum:
    buffer := ByteArray 1024 * 10
    o := pipe.to [md5sum]
    for i := 0; i < 100; i++:
      o.write buffer
    o.close

write-closed-stdin-exception:
  if file.is-file "/usr/bin/true":
    stdin := pipe.to ["/usr/bin/true"]

    expect-error "Broken pipe":
      while true:
        stdin.write
          ByteArray 1024
