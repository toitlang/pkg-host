// Copyright (C) 2019 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import host.directory show *
import host.file
import host.pipe
import host.pipe show windows-escape_
import semver
import system show platform PLATFORM-FREERTOS

test-exit-value command args expected-exit-value sleep-time/int:
  complete-args := [command] + args
  process := pipe.fork
      --create-stdin
      --create-stdout
      --create-stderr
      command
      complete-args

  task::
    if sleep-time != 0: sleep --ms=sleep-time
    process.stdin.close

  exit-value := process.wait

  expect-equals expected-exit-value (pipe.exit-code exit-value)
  expect-equals null (pipe.exit-signal exit-value)


test-exit-signal sleep-time/int:
  // Start long running process.
  process := pipe.fork
      --create-stdin
      --create-stdout
      --create-stderr
      "cat"
      ["cat"]

  SIGKILL := 9
  task::
    if sleep-time != 0: sleep --ms=sleep-time
    pipe.kill_ process.pid SIGKILL

  exit-value := process.wait

  expect-equals null (pipe.exit-code exit-value)
  expect-equals SIGKILL (pipe.exit-signal exit-value)

main:
  test-windows-escaping

  // This test does not work on ESP32 since you can't launch subprocesses.
  if platform == PLATFORM-FREERTOS: return

  test-exit-value "cat" [] 0 0
  test-exit-value "cat" [] 0 20

  test-exit-value "grep" ["foo"] 1 0
  test-exit-value "grep" ["foo"] 1 20

  test-exit-signal 0
  test-exit-signal 20

// Tests a private method in pipe.toit.
test-windows-escaping:
  expect-equals "foo" (windows-escape_ "foo")
  // Arguments with spaces are surrounded with quotes.
  // Note that in Toit syntax, quadruple quotes are really a triple quoted
  // string that starts and ends with quotes.  Your syntax colorer may not
  // understand.
  expect-equals """"foo bar"""" (windows-escape_ "foo bar")
  // Arguments with literal quotes have to be quoted and escaped.
  // In Toit literal strings we have to double backslashes, even in triple
  // quoted strings.
  expect-equals """"c:\\scare_\\"quotes\\".txt"""" (windows-escape_ """c:\\scare_"quotes".txt""")
  // Single backslashes are not escaped.  (Written as double backslashes in Toit syntax.)
  b1 := "C:\\autoexec.bat"
  expect-equals b1 (windows-escape_ b1)
  // Double backslashes are not escaped.
  b2 := "C:\\directory\\\\file.txt"
  expect-equals b2 (windows-escape_ b2)
  // Single backslashes are not escaped even at the end.
  e1 := "C:\\directory\\"
  expect-equals e1 (windows-escape_ e1)
  // Double backslashes are not escaped even at the end.
  e2 := "C:\\directory\\\\"
  expect-equals e2 (windows-escape_ e2)
  // Single backslashes are not escaped even when there are literal quotes in
  // the string, but quotes are added around, and the literal quotes are
  // escaped.
  expect-equals """"C:\\directory\\filename\\"with\\"quotes.txt"""" (windows-escape_ """C:\\directory\\filename"with"quotes.txt""")
  // A backslash at the end must be doubled if a space causes the whole string
  // to be quoted.
  expect-equals """"C:\\directory name\\\\"""" (windows-escape_ "C:\\directory name\\")
  // Two backslashes at the end must be doubled if a space causes the whole string
  // to be quoted.
  expect-equals """"C:\\directory name\\\\\\\\"""" (windows-escape_ "C:\\directory name\\\\")
  // A literal quote character preceeded by a backslash causes the backslash to
  // be turned into three backslashes.  Toit syntax makes that six backslashes.
  expect-equals """"C:\\\\\\"scare quotes\\".txt"""" (windows-escape_ """C:\\"scare quotes".txt""")
