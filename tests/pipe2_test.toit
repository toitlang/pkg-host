// Copyright (C) 2019 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import host.directory show *
import host.file
import host.pipe
import host.pipe show windows_escape_
import semver

test_exit_value command args expected_exit_value sleep_time/int:
  complete_args := [command] + args
  pipes := pipe.fork
    true  // use_path
    pipe.PIPE_CREATED  // stdin
    pipe.PIPE_CREATED  // stdiout
    pipe.PIPE_CREATED  // stderr
    command
    complete_args

  pid := pipes[3]

  task::
    if sleep_time != 0: sleep --ms=sleep_time
    pipes[0].close

  exit_value := pipe.wait_for pid

  expect_equals expected_exit_value (pipe.exit_code exit_value)
  expect_equals null (pipe.exit_signal exit_value)


test_exit_signal sleep_time/int:
  // Start long running process.
  pipes := pipe.fork
    true  // use_path
    pipe.PIPE_CREATED  // stdin
    pipe.PIPE_CREATED  // stdiout
    pipe.PIPE_CREATED  // stderr
    "cat"
    ["cat"]

  pid := pipes[3]

  SIGKILL := 9
  task::
    if sleep_time != 0: sleep --ms=sleep_time
    pipe.kill_ pid SIGKILL

  exit_value := pipe.wait_for pid

  expect_equals null (pipe.exit_code exit_value)
  expect_equals SIGKILL (pipe.exit_signal exit_value)

main:
  if platform == "Windows" and (semver.compare vm-sdk-version "v2.0.0-alpha.114") < 0:
    print "This test requires a newer version of the SDK."
    exit 0

  test_windows_escaping

  // This test does not work on ESP32 since you can't launch subprocesses.
  if platform == "FreeRTOS": return

  test_exit_value "cat" [] 0 0
  test_exit_value "cat" [] 0 20

  test_exit_value "grep" ["foo"] 1 0
  test_exit_value "grep" ["foo"] 1 20

  test_exit_signal 0
  test_exit_signal 20

// Tests a private method in pipe.toit.
test_windows_escaping:
  expect_equals "foo" (windows_escape_ "foo")
  // Arguments with spaces are surrounded with quotes.
  // Note that in Toit syntax, quadruple quotes are really a triple quoted
  // string that starts and ends with quotes.  Your syntax colorer may not
  // understand.
  expect_equals """"foo bar"""" (windows_escape_ "foo bar")
  // Arguments with literal quotes have to be quoted and escaped.
  // In Toit literal strings we have to double backslashes, even in triple
  // quoted strings.
  expect_equals """"c:\\scare_\\"quotes\\".txt"""" (windows_escape_ """c:\\scare_"quotes".txt""")
  // Single backslashes are not escaped.  (Written as double backslashes in Toit syntax.)
  b1 := "C:\\autoexec.bat"
  expect_equals b1 (windows_escape_ b1)
  // Double backslashes are not escaped.
  b2 := "C:\\directory\\\\file.txt"
  expect_equals b2 (windows_escape_ b2)
  // Single backslashes are not escaped even at the end.
  e1 := "C:\\directory\\"
  expect_equals e1 (windows_escape_ e1)
  // Double backslashes are not escaped even at the end.
  e2 := "C:\\directory\\\\"
  expect_equals e2 (windows_escape_ e2)
  // Single backslashes are not escaped even when there are literal quotes in
  // the string, but quotes are added around, and the literal quotes are
  // escaped.
  expect_equals """"C:\\directory\\filename\\"with\\"quotes.txt"""" (windows_escape_ """C:\\directory\\filename"with"quotes.txt""")
  // A backslash at the end must be doubled if a space causes the whole string
  // to be quoted.
  expect_equals """"C:\\directory name\\\\"""" (windows_escape_ "C:\\directory name\\")
  // Two backslashes at the end must be doubled if a space causes the whole string
  // to be quoted.
  expect_equals """"C:\\directory name\\\\\\\\"""" (windows_escape_ "C:\\directory name\\\\")
  // A literal quote character preceeded by a backslash causes the backslash to
  // be turned into three backslashes.  Toit syntax makes that six backslashes.
  expect_equals """"C:\\\\\\"scare quotes\\".txt"""" (windows_escape_ """C:\\"scare quotes".txt""")
