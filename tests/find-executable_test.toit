// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import host.file
import host.pipe
import system

main:
  shell/string := ?
  shell-args := ?
  if system.platform == system.PLATFORM-WINDOWS:
    // 'cmd.exe' should always be present on Windows systems.
    shell = "cmd"
    shell-args = ["/c", "echo", "hello"]
  else:
    // 'sh' should always be present on Unix-like systems.
    shell = "sh"
    shell-args = ["-c", "echo hello"]

  path := file.find-executable shell
  expect-not-null path

  // Run the found executable to verify it works.
  output := pipe.backticks [path] + shell-args
  expect-equals "hello" output.trim

  expect-null (file.find-executable "this_executable_does_not_exist")
