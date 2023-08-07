// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import host.directory show *
import host.file
import host.pipe

expect_error name [code]:
  expect_equals
    name
    catch code

expect_file_not_found cmd [code]:
  if (cmd.index_of " ") == -1:
    if platform == PLATFORM_WINDOWS:
      expect_error "Error trying to run '$cmd' using \$PATH: FILE_NOT_FOUND" code
    else:
      expect_error "Error trying to run '$cmd' using \$PATH: No such file or directory" code
  else:
    if platform == PLATFORM_WINDOWS:
      expect_error "Error trying to run executable with a space in the filename: '$cmd': FILE_NOT_FOUND" code
    else:
      expect_error "Error trying to run executable with a space in the filename: '$cmd': No such file or directory" code

if_windows windows unix:
  if platform == PLATFORM_WINDOWS: return windows
  return unix

low_level_test toit_exe:
  return
  // TODO: This is intended to test that we can have a different
  // program name to the name in arguments[0].  But it doesn't work on Windows
  // at the moment.  There was an implementation in
  // https://github.com/toitlang/toit/pull/1400, but it fails to find
  // executables without the explicit ".exe" extension, so it was annoying.
  INHERIT ::= pipe.PIPE_INHERITED
  output := pipe.OpenPipe false
  stdout := output.fd
  array := pipe.fork true INHERIT stdout INHERIT toit_exe ["ignored-0-argument", "tests/echo.toit", "horse"]
  expect_equals
    "horse"
    output.read.to_string.trim
  expect_equals
    null
    output.read

main args:
  if args.size < 1:
    print "Usage: pipe_test_slow.toit <toit_exe>"
    exit 1

  low_level_test args[0]

  // This test does not work on ESP32 since you can't launch subprocesses.
  if platform == PLATFORM_FREERTOS: return

  print " ** Some child processes will print errors on stderr during **"
  print " ** this test.  This is harmless and expected.              **"
  pipe_large_file
  write_closed_stdin_exception

  if file.is_file "/usr/bin/true":
    expect_equals
      0
      pipe.system "/usr/bin/true"

  simple_ls_command := if_windows "dir %ComSpec%" "ls /bin/sh"
  expect_equals
    0
    pipe.system
      simple_ls_command

  // run_program does not parse the command line, splitting at spaces, so it's
  // looking for a single program of the name "ls /bin/sh".
  expect_file_not_found simple_ls_command: pipe.run_program simple_ls_command

  // There's no such program as ll.
  expect_file_not_found "ll": pipe.run_program "ll" "/bin/sh"

  expect_equals
    0
    pipe.run_program "ls" "/bin/sh"

  // Increase the heap size a bit so that frequent GCs do not clean up file descriptors.
  a := []
  100.repeat:
    a.add "$it"

  // If backticks doesn't clean up open file descriptors, this will run out of
  // them.  Sadly, Windows is astonishingly slow at starting subprocesses.
  (platform == PLATFORM_WINDOWS ? 100 : 2000).repeat:
    expect_equals
      ""
      pipe.backticks "true"

  expect_equals
    "/bin/sh\n"
    pipe.backticks "ls" "/bin/sh"

  no_exist_cmd := "a program name that does not exist"
  expect_file_not_found no_exist_cmd : pipe.to no_exist_cmd

  tmpdir := mkdtemp "/tmp/toit_file_test_"
  old_current_directory := cwd

  try:
    chdir tmpdir

    filename := "test.out"
    dirname := "testdir"

    mkdir dirname
    go_up := false

    try:
      p := pipe.to "sh" "-c" "tr A-Z a-z > $dirname/$filename"
      p.write "The contents of the file"
      p.close

      expect (file.size "$dirname/$filename") != null

      chdir dirname
      go_up = true

      output := ""
      if platform == PLATFORM_WINDOWS:
        p = pipe.from "certutil" "-hashfile" filename
        while byte_array := p.read:
          output += byte_array.to_string

        expect output == "SHA1 hash of $filename:\r\n2dcc8e172c72f3d6937d49be7cf281067d257a62\r\nCertUtil: -hashfile command completed successfully.\r\n"
      else:
        p = pipe.from "shasum" filename
        while byte_array := p.read:
          output += byte_array.to_string

        expect output == "2dcc8e172c72f3d6937d49be7cf281067d257a62  $filename\n"

      chdir ".."
      go_up = false

    finally:
      if go_up:
        chdir ".."
      file.delete "$dirname/$filename"
      rmdir dirname

  finally:
    rmdir --recursive tmpdir

  chdir old_current_directory

  if platform == PLATFORM_WINDOWS:
    expect_error "certutil: exited with status 2":
      p := pipe.from "certutil" "file_that_doesn't exist"
      while p.read:
        // Do nothing.

    expect_error "certutil: exited with status 2":
      sum := pipe.backticks "certutil" "file_that_doesn't exist"
  else:
    expect_error "shasum: exited with status 1":
      p := pipe.from "shasum" "file_that_doesn't exist"
      while p.read:
        // Do nothing.

    expect_error "shasum: exited with status 1":
      sum := pipe.backticks "shasum" "file_that_doesn't exist"

  tar_exit_code := (platform == PLATFORM_LINUX) ? 2 : 1
  expect_error "tar: exited with status $tar_exit_code":
    p := pipe.to "tar" "-xvf" "-" "foo.txt"
    p.close  // Close without sending a valid tar file.

  task:: long_running_sleep

  // Exit explicitly - this will interrupt the task that is just waiting for
  // the subprocess to exit.
  exit 0

// Task that is interrupted by an explicit exit.
long_running_sleep:
  pipe.run_program "sleep" "1000"

/// Returns whether a path exists and is a character device.
is_char_device name --follow_links/bool=true -> bool:
  stat := file.stat name --follow_links
  if not stat: return false
  return stat[file.ST_TYPE] == file.CHARACTER_DEVICE

pipe_large_file:
  md5sum/string? := null
  if platform == PLATFORM_WINDOWS:
    GIT_MD5SUM := "c:/Program Files/Git/usr/bin/md5sum.exe"
    if file.is_file GIT_MD5SUM:
      md5sum = GIT_MD5SUM
  else if platform == PLATFORM_MACOS:
    md5sum = "md5"
  else:
    md5sum = "md5sum"
  if md5sum:
    buffer := ByteArray 1024 * 10
    o := pipe.to [md5sum]
    for i := 0; i < 100; i++:
      o.write buffer
    o.close

write_closed_stdin_exception:
  if file.is_file "/usr/bin/true":
    stdin := pipe.to ["/usr/bin/true"]

    expect_error "Broken pipe":
      while true:
        stdin.write
          ByteArray 1024
