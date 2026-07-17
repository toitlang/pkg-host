// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import host.file
import host.os
import host.pipe
import system

main:
  test-shell
  test-empty-path-entry
  expect-null (file.find-executable "this_executable_does_not_exist")

test-shell:
  shell/string := ?
  shell-args := ?
  if system.platform == system.PLATFORM-WINDOWS:
    // 'cmd.exe' should always be present on Windows systems.
    shell = "cmd"
    shell-args = ["/c", "echo hello"]
  else:
    // 'sh' should always be present on Unix-like systems.
    shell = "sh"
    shell-args = ["-c", "echo hello"]

  path := file.find-executable shell
  expect-not-null path

  // The path must join the PATH entry and the name with a single separator.
  if system.platform == system.PLATFORM-WINDOWS:
    expect-not (path.contains "\\\\")
    expect-not (path.contains "/\\")
  else:
    expect-not (path.contains "//")

  // Run the found executable to verify it works.
  output := pipe.backticks [path] + shell-args
  expect-equals "hello" output.trim

/**
Tests that an empty entry of the PATH is treated as the current directory.
*/
test-empty-path-entry:
  is-windows := system.platform == system.PLATFORM-WINDOWS
  separator := is-windows ? "\\" : "/"
  name := "find-executable-tool"
  // On Windows the extension must be one of the PATHEXT entries, which we
  // pin below.
  filename := is-windows ? "$(name).bat" : name

  old-path := os.env.get "PATH"
  old-pathext := os.env.get "PATHEXT"
  file.write-contents "" --path=filename --permissions=0b111_101_101

  // A trailing separator leaves an empty entry at the end of the PATH.
  // The tool only exists in the current directory, so it can only be found
  // through that empty entry.
  os.env["PATH"] = is-windows ? "C:\\does-not-exist;" : "/does-not-exist:"
  if is-windows: os.env["PATHEXT"] = ".bat"
  expect-equals ".$separator$filename" (file.find-executable name)

  file.delete filename
  if old-path: os.env["PATH"] = old-path
  if old-pathext: os.env["PATHEXT"] = old-pathext
